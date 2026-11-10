#!/usr/bin/env python3
"""Test M1 with real Expect and a fake SSH process; no network or host changes.

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
name = os.environ.get("MOCK_ROUTER_NAME") or ("hq-rtr" if ip == "172.16.1.2" else "br-rtr")
peer = os.environ.get("MOCK_GRE_PEER", "10.10.10.2")
tunnel = os.environ.get("MOCK_TUNNEL", "tunnel.0")

def say(text):
    sys.stdout.write(text)
    sys.stdout.flush()

def record(command, kind="command"):
    with open(os.environ["MOCK_LOG"], "a") as output:
        output.write(json.dumps({"ip": ip, "command": command, "kind": kind}) + "\n")

if mode == "auth_failure":
    say("Permission denied (publickey,password).\n")
    sys.exit(255)

record(sys.argv[1:], "argv")
say("Password: ")
sys.stdin.readline()
if mode == "timeout":
    time.sleep(8)
    sys.exit(255)

current = name if os.environ.get("MOCK_EXISTING_NAME") == "1" else "ecorouter"
say("\n" + current + "> ")
config = False
ospf_calls = 0
for line in sys.stdin:
    command = line.rstrip("\r\n")
    record(command)
    if mode == "disconnect" and command.startswith("hostname "):
        sys.exit(255)
    if mode == "command_timeout" and command.startswith("hostname "):
        time.sleep(8)
        sys.exit(255)
    if mode == "cli_error" and command.startswith("ip domain-name"):
        say("\n% Invalid input detected at '^' marker.\n" + current + "(config)# ")
        continue
    if mode == "save_error" and command == "write memory":
        say("\nError: failed to save configuration\n" + current + "# ")
        continue
    if command == "ping":
        questions = (
            "Protocol [ip]: ", "Target IP address: ", "Name of the VRF : ",
            "Repeat count [5]: ", "Datagram size [100]: ",
            "Timeout in seconds [2]: ", "Extended commands [n]: ",
            "Broadcast [n]: ",
        )
        replies = []
        for question in questions:
            say(question)
            reply = sys.stdin.readline().rstrip("\r\n")
            record(reply, "ping-input")
            replies.append(reply)
        target = replies[1]
        count = replies[3] or "5"
        say("\nPING " + target + " (" + target + ") 100(128) bytes of data.\n")
        if mode != "gre_loss":
            received = 3 if mode == "gre_partial_loss" else int(count)
            for index in range(1, received + 1):
                say("108 bytes from " + target + ": icmp_seq=" + str(index) + " ttl=64 time=0.5 ms\n")
        say("\n--- " + target + " ping statistics ---\n")
        if mode == "gre_loss":
            say(count + " packets transmitted, 0 received, 100% packet loss, time 3000ms\n")
        elif mode == "gre_partial_loss":
            say(count + " packets transmitted, 3 received, 25% packet loss, time 3000ms\n")
        else:
            say(count + " packets transmitted, " + count + " received, 0% packet loss, time 3000ms\n")
        say(current + "# ")
        continue
    if command.startswith("show ip ospf neighbor"):
        ospf_calls += 1
        say("\nTotal number of full neighbors: 1\nOSPF process 1 VRF(default):\n")
        say("Neighbor ID Pri State Dead Time Address Interface Instance\n")
        if mode == "ospf_other_peer":
            say("10.20.10.2 1 Full/DR 00:00:30 10.20.10.2 " + tunnel + " 0\n")
        elif mode == "ospf_wrong_interface":
            say(peer + " 1 Full/Backup 00:00:30 " + peer + " fw 0\n")
        elif mode == "ospf_split_rows":
            say(peer + " 1 Init/Backup 00:00:30 " + peer + " " + tunnel + " 0\n")
            say("10.20.10.2 1 Full/DR 00:00:30 10.20.10.2 fw 0\n")
        elif mode == "ospf_never_full" or (mode == "ospf_wait" and ospf_calls < 3):
            say(peer + " 1 Init/Backup 00:00:30 " + peer + " " + tunnel + " 0\n")
        else:
            say(peer + " 1 Full/Backup 00:00:30 " + peer + " " + tunnel + " 0\n")
        say(current + "# ")
        continue
    if command.startswith("show interface"):
        state = "down" if mode == "gre_if_down" else "up"
        tunnel_mode = "IPIP" if mode == "gre_wrong_mode" else "GRE"
        say("\nInterface " + tunnel + " is " + state + ", line protocol is " + state + "\nTunnel mode: " + tunnel_mode + "\n")
        say(current + "# ")
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

    def run_router(self, ip, mode="success", existing=False, action="configure", extra_env=None):
        with tempfile.TemporaryDirectory(prefix="banan-m1-test-") as directory:
            root = Path(directory)
            binary_dir = root / "bin"
            binary_dir.mkdir()
            ssh = binary_dir / "ssh"
            ssh.write_text(MOCK_SSH)
            ssh.chmod(0o755)
            for binary in ("hostnamectl", "timedatectl", "iptables", "iptables-save", "systemctl", "apt-get", "ping"):
                blocked = binary_dir / binary
                blocked.write_text('#!/bin/sh\nprintf "Unexpected host operation in dialogue test\\n" >&2\nexit 97\n')
                blocked.chmod(0o755)
            # Run a copy so the test can bound old and new timeout spellings.
            script = root / "isp.sh"
            script.write_text(self.source.replace("set timeout 30", "set timeout 1"))
            log = root / "commands.jsonl"
            environment = os.environ.copy()
            environment.update({
                "PATH": str(binary_dir) + os.pathsep + environment["PATH"],
                "MOCK_MODE": mode,
                "MOCK_EXISTING_NAME": "1" if existing else "0",
                "MOCK_LOG": str(log),
                "SSH_TIMEOUT": "2",
                "CLI_TIMEOUT": "2",
                "OSPF_WAIT_TIMEOUT": "3",
                "OSPF_POLL_INTERVAL": "1",
            })
            environment.update(extra_env or {})
            name = "hq-rtr" if ip == "172.16.1.2" else "br-rtr"
            name = environment.get("MOCK_ROUTER_NAME", name)
            peer = environment.get("MOCK_GRE_PEER", "10.10.10.2" if name == "hq-rtr" else "10.10.10.1")
            environment["MOCK_GRE_PEER"] = peer
            process = subprocess.Popen(
                ["bash", "-c", 'source "$1"; if [[ $4 == check ]]; then check_router "$2" "$3" "$5"; else configure_router "$2" "$3"; fi',
                 "local-router-test", str(script), name, ip, action, peer],
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
            events = []
            if log.exists():
                events = [json.loads(line) for line in log.read_text().splitlines()]
                commands = [event["command"] for event in events if event["kind"] == "command"]
            return process.returncode, commands, output, events

    def test_original_commands_preserved_for_both_routers(self):
        for ip, (count, fingerprint) in BASELINE.items():
            for existing in (False, True):
                with self.subTest(ip=ip, existing_hostname=existing):
                    code, commands, output, _ = self.run_router(ip, existing=existing)
                    self.assertEqual(code, 0, output)
                    self.assertEqual(output, "", "Successful configuration must be silent")
                    self.assertEqual(len(commands), count, output)
                    actual = hashlib.sha256("\n".join(commands).encode()).hexdigest()
                    self.assertEqual(actual, fingerprint, output)

    def test_remote_failures_are_reported(self):
        cases = {
            "auth_failure": ("Permission denied (publickey,password).", None),
            "cli_error": ("% Invalid input detected at '^' marker.", "ip domain-name au-team.irpo"),
            "save_error": ("Error: failed to save configuration", "write memory"),
            "disconnect": (None, "hostname hq-rtr"),
            "timeout": (None, None),
            "command_timeout": (None, "hostname hq-rtr"),
            "ssh_status": (None, "exit"),
        }
        for mode, (message, last_command) in cases.items():
            with self.subTest(mode=mode):
                code, commands, output, _ = self.run_router("172.16.1.2", mode=mode)
                self.assertNotEqual(code, 0, output)
                self.assertTrue(output.strip(), "A failure must retain a diagnostic")
                if message is not None:
                    self.assertIn(message, output)
                if last_command is None:
                    self.assertEqual(commands, [], output)
                else:
                    self.assertTrue(commands, output)
                    self.assertEqual(commands[-1], last_command, output)

    def test_gre_ping_is_finite_four_packets_and_silent_on_success(self):
        for ip in BASELINE:
            with self.subTest(ip=ip):
                code, commands, output, events = self.run_router(ip, action="check")
                self.assertEqual(code, 0, output)
                self.assertEqual(output, "")
                self.assertIn("ping", commands)
                inputs = [event["command"] for event in events if event["kind"] == "ping-input"]
                self.assertEqual(len(inputs), 8)
                self.assertEqual(inputs[1], "10.10.10.2" if ip == "172.16.1.2" else "10.10.10.1")
                self.assertEqual(inputs[3], "4")

    def test_total_gre_loss_is_failure_and_retains_native_statistics(self):
        code, _, output, _ = self.run_router("172.16.1.2", action="check", mode="gre_loss")
        self.assertNotEqual(code, 0, output)
        self.assertIn("4 packets transmitted, 0 received, 100% packet loss", output)

    def test_partial_gre_loss_is_failure(self):
        code, _, output, _ = self.run_router("172.16.1.2", action="check", mode="gre_partial_loss")
        self.assertNotEqual(code, 0, output)
        self.assertIn("4 packets transmitted, 3 received, 25% packet loss", output)

    def test_down_gre_interface_is_failure_even_if_ping_receives_answers(self):
        code, _, output, _ = self.run_router("172.16.1.2", action="check", mode="gre_if_down")
        self.assertNotEqual(code, 0, output)
        self.assertIn("Interface tunnel.0 is down, line protocol is down", output)

    def test_ipip_is_not_accepted_as_gre_even_if_interface_and_ping_are_up(self):
        code, _, output, _ = self.run_router("172.16.1.2", action="check", mode="gre_wrong_mode")
        self.assertNotEqual(code, 0, output)
        self.assertIn("Tunnel mode: IPIP", output)

    def test_ospf_waits_for_full_adjacency(self):
        code, commands, output, _ = self.run_router("172.16.1.2", action="check", mode="ospf_wait")
        self.assertEqual(code, 0, output)
        self.assertEqual(output, "")
        self.assertEqual(commands.count("show ip ospf neighbor"), 3)

    def test_ospf_rejects_other_neighbors_interfaces_and_split_rows(self):
        for mode in ("ospf_never_full", "ospf_other_peer", "ospf_wrong_interface", "ospf_split_rows"):
            with self.subTest(mode=mode):
                code, commands, output, _ = self.run_router("172.16.1.2", action="check", mode=mode)
                self.assertNotEqual(code, 0, output)
                self.assertIn("Neighbor ID", output)
                self.assertLessEqual(commands.count("show ip ospf neighbor"), 4)

    def test_configuration_parameters_are_passed_as_data(self):
        environment = {
            "HQ_RTR_NAME": "hq-test",
            "HQ_RTR_IP": "192.0.2.2",
            "HQ_GRE_ADDRESS": "10.77.0.1/30",
            "BR_RTR_IP": "192.0.2.3",
            "DOMAIN_NAME": "lab.example",
            "DNS_IP": "192.0.2.53",
            "TUNNEL_IF": "tunnel.7",
            "OSPF_ID": "7",
            "OSPF_KEY_ID": "3",
            "OSPF_KEY": "key$[safe]",
            "MOCK_ROUTER_NAME": "hq-test",
            "MOCK_TUNNEL": "tunnel.7",
        }
        code, commands, output, _ = self.run_router("192.0.2.2", extra_env=environment)
        self.assertEqual(code, 0, output)
        self.assertEqual(output, "")
        for command in (
            "hostname hq-test", "ip domain-name lab.example", "ip name-server 192.0.2.53",
            "interface tunnel.7", "ip address 10.77.0.1/30",
            "ip tunnel 192.0.2.2 192.0.2.3 mode gre", "router ospf 7",
            "ip ospf message-digest-key 3 md5 key$[safe]",
        ):
            self.assertIn(command, commands)

    def test_check_uses_overridden_peer_and_tunnel(self):
        code, commands, output, events = self.run_router(
            "172.16.1.2", action="check", extra_env={
                "TUNNEL_IF": "tunnel.7", "MOCK_TUNNEL": "tunnel.7",
                "MOCK_GRE_PEER": "10.77.0.2",
            },
        )
        self.assertEqual(code, 0, output)
        self.assertEqual(output, "")
        inputs = [event["command"] for event in events if event["kind"] == "ping-input"]
        self.assertEqual(inputs[1], "10.77.0.2")


if __name__ == "__main__":
    unittest.main(verbosity=2)
