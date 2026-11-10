#!/usr/bin/env python3
"""Test the M1 router dialogue locally; no host configuration or network access.

Uses real Expect and a fake ssh executable. Command fingerprints were recorded
from hq-rtr.sh at 7c525dd3c3a4b2a9a5aeda81df202e239e9edb34 before the merge.
Run: python3 m1/tests/test_router_dialogue.py
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest


ISP_SCRIPT = Path(__file__).resolve().parents[1] / "isp.sh"
BASELINE = {
    "172.16.1.2": (45, "be5860da89f64fb2e503cba7f8d45a58678dfb44cd0f71cd51744c4842b1b663"),
    "172.16.2.2": (42, "09489bb676ac93b46903755a7aae29c48ff8c59028eff5b4182964f52afbcea3"),
}

MOCK_SSH = r'''#!/usr/bin/env python3
import json
import os
import sys
import time

mode = os.environ.get("MOCK_MODE", "success")
ip = sys.argv[-1].split("@")[-1]
name = "hq-rtr" if ip == "172.16.1.2" else "br-rtr"

def say(text):
    sys.stdout.write(text)
    sys.stdout.flush()

def record(command):
    with open(os.environ["MOCK_LOG"], "a") as output:
        output.write(json.dumps({"ip": ip, "command": command}) + "\n")

if mode == "auth_failure":
    say("Permission denied (publickey,password).\n")
    sys.exit(255)

say("Password: ")
sys.stdin.readline()
if mode == "timeout":
    time.sleep(8)
    sys.exit(255)

current = name if os.environ.get("MOCK_EXISTING_NAME") == "1" else "ecorouter"
say("\n" + current + "> ")
config = False
for line in sys.stdin:
    command = line.rstrip("\r\n")
    record(command)
    if mode == "disconnect" and command.startswith("hostname "):
        sys.exit(255)
    if mode == "cli_error" and command.startswith("ip domain-name"):
        say("\n% Invalid input detected at '^' marker.\n" + current + "(config)# ")
        continue
    if mode == "save_error" and command == "write memory":
        say("\nError: failed to save configuration\n" + current + "# ")
        continue
    if command == "configure":
        config = True
    elif command.startswith("hostname "):
        current = command.split(" ", 1)[1]
    elif command == "end":
        config = False
    elif command == "exit" and not config:
        sys.exit(17 if mode == "ssh_status" else 0)
    say("\n" + current + ("(config)# " if config else "# "))
'''


class RouterDialogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.expect = shutil.which("expect")
        if cls.expect is None:
            raise unittest.SkipTest("Expect is required for the local dialogue tests")
        cls.source = ISP_SCRIPT.read_text()
        if "BASH_SOURCE" not in cls.source or "configure_router()" not in cls.source:
            raise RuntimeError("Expected source-safe ISP script with configure_router()")

    def run_router(self, ip, mode="success", existing=False):
        with tempfile.TemporaryDirectory(prefix="banan-m1-test-") as directory:
            root = Path(directory)
            binary_dir = root / "bin"
            binary_dir.mkdir()
            ssh = binary_dir / "ssh"
            ssh.write_text(MOCK_SSH)
            ssh.chmod(0o755)
            # Speed up only the negative timeout case; production stays at 30s.
            script = root / "isp.sh"
            script.write_text(self.source.replace("set timeout 30", "set timeout 1"))
            log = root / "commands.jsonl"
            environment = os.environ.copy()
            environment.update({
                "PATH": str(binary_dir) + os.pathsep + environment["PATH"],
                "MOCK_MODE": mode,
                "MOCK_EXISTING_NAME": "1" if existing else "0",
                "MOCK_LOG": str(log),
            })
            name = "hq-rtr" if ip == "172.16.1.2" else "br-rtr"
            process = subprocess.Popen(
                ["bash", "-c", 'source "$1"; configure_router "$2" "$3"',
                 "local-router-test", str(script), name, ip],
                env=environment, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, start_new_session=True,
            )
            try:
                output, _ = process.communicate(timeout=6)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                output, _ = process.communicate()
                self.fail("Dialogue exceeded its deadline:\n" + output)
            commands = []
            if log.exists():
                commands = [json.loads(line)["command"] for line in log.read_text().splitlines()]
            return process.returncode, commands, output

    def test_original_commands_preserved_for_both_routers(self):
        for ip, (count, fingerprint) in BASELINE.items():
            for existing in (False, True):
                with self.subTest(ip=ip, existing_hostname=existing):
                    code, commands, output = self.run_router(ip, existing=existing)
                    self.assertEqual(code, 0, output)
                    self.assertEqual(len(commands), count, output)
                    actual = hashlib.sha256("\n".join(commands).encode()).hexdigest()
                    self.assertEqual(actual, fingerprint, output)

    def test_remote_failures_are_reported(self):
        cases = {
            "auth_failure": ("ошибка подключения", None),
            "cli_error": ("ошибка CLI", "ip domain-name au-team.irpo"),
            "save_error": ("ошибка CLI", "write memory"),
            "disconnect": ("SSH завершился во время команды", "hostname hq-rtr"),
            "timeout": ("таймаут подключения", None),
            "ssh_status": ("SSH завершился с ошибкой", "exit"),
        }
        for mode, (message, last_command) in cases.items():
            with self.subTest(mode=mode):
                code, commands, output = self.run_router("172.16.1.2", mode=mode)
                self.assertNotEqual(code, 0, output)
                self.assertIn(message, output)
                if last_command is None:
                    self.assertEqual(commands, [], output)
                else:
                    self.assertTrue(commands, output)
                    self.assertEqual(commands[-1], last_command, output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
