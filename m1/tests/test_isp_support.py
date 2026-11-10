#!/usr/bin/env python3
"""Exercise ISP helpers against temporary ALT/APT fixtures and local command stubs.

No package installation, real ping, host configuration, or network access occurs.
Run: python3 -m unittest discover -s m1/tests -v
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ISP_SCRIPT = Path(__file__).resolve().parents[1] / "isp.sh"
SOURCE_LINE = "rpm [p10] http://ftp.altlinux.org/pub/distributions/ALTLinux p10/branch/x86_64 classic\n"

PING_STUB = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["COMMAND_LOG"], "a") as output:
    output.write(json.dumps(["ping"] + sys.argv[1:]) + "\n")
count = next((sys.argv[index + 1] if argument == "-c" else argument[2:])
             for index, argument in enumerate(sys.argv) if argument.startswith("-c"))
target = sys.argv[-1]
if count == "1":
    print("HIDDEN ONE PACKET PROBE")
    sys.exit(1 if os.environ.get("PING_FAIL") == "1" else 0)
print("PING " + target + " (" + target + ") 56(84) bytes of data.")
print("From 172.16.1.1 icmp_seq=1 Destination Host Unreachable")
print("--- " + target + " ping statistics ---")
print("4 packets transmitted, 0 received, +4 errors, 100% packet loss")
sys.exit(1)
'''

NATIVE_STUB = r'''#!/usr/bin/env python3
import os, pathlib, sys
counter = pathlib.Path(os.environ["NATIVE_COUNTER"])
attempt = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(attempt))
print("native stdout diagnostic")
print("native stderr diagnostic", file=sys.stderr)
sys.exit(0 if attempt > int(os.environ.get("NATIVE_FAILURES", "0")) else 23)
'''

APT_STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
with open(os.environ["COMMAND_LOG"], "a") as output:
    output.write(json.dumps(["apt-get"] + sys.argv[1:]) + "\n")
stage = "update" if "update" in sys.argv else "install" if "install" in sys.argv else "other"
counter = pathlib.Path(os.environ["APT_COUNTER_PREFIX"] + stage)
attempt = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(attempt))
print("APT native " + stage + " output")
if attempt <= int(os.environ.get("APT_FAIL_" + stage.upper(), "0")):
    print("E: fixture " + stage + " failure", file=sys.stderr)
    sys.exit(100)
if stage == "install":
    pathlib.Path(os.environ["MOCK_DEPENDENCIES_READY"]).touch()
'''

# Simulate missing commands without hiding the host's shell or running installs.
DEPENDENCY_AVAILABILITY = r'''
command() {
    if [[ ${1:-} == -v ]]; then
        case ${2:-} in
            expect|ssh|curl)
                [[ -f $MOCK_DEPENDENCIES_READY ]] || return 1
                printf '/fixture/bin/%s\n' "$2"
                return 0
                ;;
            ping|ip|iptables|iptables-save|hostnamectl|timedatectl|systemctl)
                printf '/fixture/bin/%s\n' "$2"
                return 0
                ;;
        esac
    fi
    builtin command "$@"
}
'''


class ISPSupportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="banan-isp-support-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.sources = self.root / "sources.list"
        self.sources.write_text(SOURCE_LINE)
        self.sources_dir = self.root / "sources.list.d"
        self.sources_dir.mkdir()
        self.os_release = self.root / "os-release"
        self.os_release.write_text('ID=altlinux\nVERSION_ID="10.4"\n')
        self.log = self.root / "commands.jsonl"
        self.environment = os.environ.copy()
        self.environment.update({
            "PATH": str(self.bin) + os.pathsep + self.environment["PATH"],
            "OS_RELEASE_FILE": str(self.os_release),
            "APT_SOURCES_FILE": str(self.sources),
            "APT_SOURCES_DIR": str(self.sources_dir),
            "SYS_NETWORK_FILE": str(self.root / "network"),
            "IPTABLES_STATE_FILE": str(self.root / "iptables"),
            "COMMAND_LOG": str(self.log),
            "NATIVE_COUNTER": str(self.root / "native-counter"),
            "APT_COUNTER_PREFIX": str(self.root / "apt-counter-"),
            "MOCK_DEPENDENCIES_READY": str(self.root / "dependencies-ready"),
            "ALT_BRANCH": "p10",
            "ALT_ARCH": "x86_64",
            "REPOSITORY_MIRROR": "http://mirror.yandex.ru/altlinux",
            "APT_ATTEMPTS": "3",
            "APT_RETRY_DELAY": "0",
            "PING_COUNT": "4",
            "PING_TIMEOUT": "1",
        })
        self.stub("ping", PING_STUB)
        self.stub("native-command", NATIVE_STUB)
        self.stub("apt-get", APT_STUB)
        for binary in ("hostnamectl", "timedatectl", "iptables", "iptables-save"):
            self.stub(binary, '#!/bin/sh\nprintf "Unexpected host operation in support test\\n" >&2\nexit 97\n')
        self.stub("rpm", '#!/bin/sh\nprintf "systemd-fixture\\n"\n')
        self.stub("systemctl", '#!/bin/sh\nif [ "$1" = show ]; then printf "fixture-systemd-version\\n"; else printf "Unexpected systemctl mutation\\n" >&2; exit 97; fi\n')

    def stub(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_function(self, shell, extra_env=None):
        environment = self.environment.copy()
        environment.update(extra_env or {})
        return subprocess.run(
            ["bash", "-c", 'source "$1"; set -e; ' + shell, "isp-support-test", str(ISP_SCRIPT)],
            env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=8,
        )

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def repository_snapshot(self):
        paths = list(self.root.glob("sources.list*")) + list(self.sources_dir.rglob("*"))
        return {str(path.relative_to(self.root)): path.read_bytes() for path in paths if path.is_file()}

    @staticmethod
    def ping_count(arguments):
        return next((arguments[index + 1] if argument == "-c" else argument[2:])
                    for index, argument in enumerate(arguments) if argument.startswith("-c"))

    def test_sourcing_only_defines_helpers(self):
        result = self.run_function(":")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.commands(), [])
        self.assertEqual(self.sources.read_text(), SOURCE_LINE)

    def test_quiet_run_success_is_silent(self):
        result = self.run_function("quiet_run native-command")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")

    def test_quiet_run_preserves_native_error_and_status(self):
        result = self.run_function("quiet_run native-command", {"NATIVE_FAILURES": "9"})
        self.assertEqual(result.returncode, 23, result.stdout)
        self.assertIn("native stdout diagnostic", result.stdout)
        self.assertIn("native stderr diagnostic", result.stdout)
        self.assertNotIn("[ERROR]", result.stdout)

    def test_retry_recovers_silently_and_has_a_bound(self):
        result = self.run_function("retry_quiet 3 native-command", {"NATIVE_FAILURES": "2"})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual((self.root / "native-counter").read_text(), "3")

    def test_retry_exhaustion_retains_final_diagnostic(self):
        result = self.run_function("retry_quiet 3 native-command", {"NATIVE_FAILURES": "9"})
        self.assertEqual(result.returncode, 23, result.stdout)
        self.assertEqual((self.root / "native-counter").read_text(), "3")
        self.assertIn("native stdout diagnostic", result.stdout)
        self.assertIn("native stderr diagnostic", result.stdout)

    def test_router_probe_is_hidden_when_reachable(self):
        result = self.run_function('check_wan_router 172.16.1.2')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(len(self.commands()), 1)
        self.assertEqual(self.ping_count(self.commands()[0]), "1")

    def test_unreachable_router_prints_four_packet_native_ping_and_stops(self):
        result = self.run_function('check_wan_router 172.16.1.2; printf SHOULD_NOT_CONTINUE', {"PING_FAIL": "1"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("HIDDEN ONE PACKET PROBE", result.stdout)
        self.assertNotIn("SHOULD_NOT_CONTINUE", result.stdout)
        self.assertIn("Destination Host Unreachable", result.stdout)
        self.assertIn("4 packets transmitted, 0 received, +4 errors, 100% packet loss", result.stdout)
        self.assertNotIn("[ERROR]", result.stdout)
        self.assertEqual(len(self.commands()), 2)
        self.assertEqual([self.ping_count(args) for args in self.commands()], ["1", "4"])

    def test_mirror_replacement_is_branch_preserving_and_idempotent(self):
        original = self.sources.read_bytes()
        result = self.run_function("setup_yandex_repository")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        first = self.sources.read_bytes()
        self.assertIn(b"mirror.yandex.ru/altlinux", first)
        self.assertIn(b"p10/branch", first)
        self.assertNotIn(b"p11/branch", first)
        self.assertEqual(Path(str(self.sources) + ".banan-m1.bak").read_bytes(), original)
        snapshot = self.repository_snapshot()
        result = self.run_function("setup_yandex_repository")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.sources.read_bytes(), first)
        self.assertEqual(Path(str(self.sources) + ".banan-m1.bak").read_bytes(), original)
        self.assertEqual(self.repository_snapshot(), snapshot)

    def test_p11_is_supported_only_with_explicit_matching_branch(self):
        self.sources.write_text(SOURCE_LINE.replace("p10", "p11"))
        self.os_release.write_text('ID=altlinux\nVERSION_ID="11.0"\n')
        result = self.run_function("setup_yandex_repository", {"ALT_BRANCH": "p11"})
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("p11/branch", self.sources.read_text())
        self.assertNotIn("p10/branch", self.sources.read_text())

    def test_branch_override_cannot_migrate_an_active_p10_source(self):
        before = self.repository_snapshot()
        result = self.run_function("setup_yandex_repository", {"ALT_BRANCH": "p11"})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.repository_snapshot(), before)

    def test_mirror_preserves_branch_when_it_is_in_the_base_url(self):
        self.sources.write_text("rpm [p10] http://ftp.altlinux.org/pub/distributions/ALTLinux/p10/branch x86_64 classic\n")
        result = self.run_function("setup_yandex_repository")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.sources.read_text(), "rpm [p10] http://mirror.yandex.ru/altlinux/p10/branch x86_64 classic\n")

    def test_third_party_sources_are_preserved(self):
        other = self.sources_dir / "third-party.list"
        content = "rpm [p10] http://example.invalid/custom p10/branch/x86_64 classic\n"
        other.write_text(content)
        result = self.run_function("setup_yandex_repository")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(other.read_text(), content)
        self.assertFalse(Path(str(other) + ".banan-m1.bak").exists())

    def test_mixed_or_unknown_sources_are_rejected_before_any_write(self):
        cases = {
            "mixed": (SOURCE_LINE + SOURCE_LINE.replace("p10", "p11"), {}),
            "unknown_active": ("rpm [alt] http://ftp.altlinux.org/pub/distributions/ALTLinux/Sisyphus x86_64 classic\n", {}),
            "unsupported_active": (SOURCE_LINE.replace("p10", "p9"), {}),
            "unknown_empty": ("", {"ALT_BRANCH": ""}),
        }
        for label, (content, environment) in cases.items():
            with self.subTest(label=label):
                self.sources.write_text(content)
                version = "99.0" if label == "unknown_empty" else "10.4"
                self.os_release.write_text('ID=altlinux\nVERSION_ID="' + version + '"\n')
                before = self.repository_snapshot()
                result = self.run_function("setup_yandex_repository", environment)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertTrue(result.stdout.strip())
                self.assertEqual(self.sources.read_text(), content)
                self.assertFalse(Path(str(self.sources) + ".banan-m1.bak").exists())
                self.assertEqual(self.repository_snapshot(), before)

    def test_mixed_branches_across_source_files_are_rejected_without_writes(self):
        other = self.sources_dir / "additional.list"
        other.write_text(SOURCE_LINE.replace("p10", "p11"))
        before = self.repository_snapshot()
        result = self.run_function("setup_yandex_repository")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.sources.read_text(), SOURCE_LINE)
        self.assertEqual(other.read_text(), SOURCE_LINE.replace("p10", "p11"))
        self.assertFalse(Path(str(self.sources) + ".banan-m1.bak").exists())
        self.assertEqual(self.repository_snapshot(), before)

    def test_confirmed_p10_adds_classic_arch_and_noarch_when_no_network_source_exists(self):
        for content in ("", "# " + SOURCE_LINE, "rpm cdrom:[ALT Server 10.4] / classic\n"):
            with self.subTest(content=content):
                self.sources.write_text(content)
                for file in self.sources_dir.iterdir():
                    file.unlink()
                result = self.run_function("setup_yandex_repository")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(result.stdout, "")
                snapshot = self.repository_snapshot()
                active = [
                    line for path, data in snapshot.items() if not path.endswith(".banan-m1.bak")
                    for line in data.decode().splitlines() if line.lstrip().startswith("rpm ")
                    and "mirror.yandex.ru/altlinux" in line
                ]
                self.assertTrue(any("p10/branch/x86_64" in line and "classic" in line for line in active), active)
                self.assertTrue(any("p10/branch/noarch" in line and "classic" in line for line in active), active)
                self.assertFalse(any("p11/branch" in line for line in active), active)
                result = self.run_function("setup_yandex_repository")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.repository_snapshot(), snapshot)

    def test_non_alt_host_is_rejected_before_repository_writes(self):
        self.os_release.write_text('ID=debian\nVERSION_ID="12"\n')
        before = self.repository_snapshot()
        result = self.run_function("setup_yandex_repository")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.sources.read_text(), SOURCE_LINE)
        self.assertFalse(Path(str(self.sources) + ".banan-m1.bak").exists())
        self.assertEqual(self.repository_snapshot(), before)

    def test_existing_dependencies_need_no_package_operations(self):
        Path(self.environment["MOCK_DEPENDENCIES_READY"]).touch()
        result = self.run_function(DEPENDENCY_AVAILABILITY + "ensure_dependencies")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.commands(), [])

    def test_missing_dependencies_are_installed_with_bounded_silent_retries(self):
        result = self.run_function(
            DEPENDENCY_AVAILABILITY + "ensure_dependencies",
            {"APT_FAIL_UPDATE": "2", "APT_FAIL_INSTALL": "1"},
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        commands = self.commands()
        self.assertEqual(sum("update" in args for args in commands), 3)
        self.assertEqual(sum("install" in args for args in commands), 2)
        self.assertTrue(Path(self.environment["MOCK_DEPENDENCIES_READY"]).exists())

    def test_package_update_failure_stops_before_install_and_keeps_native_error(self):
        result = self.run_function(
            DEPENDENCY_AVAILABILITY + "ensure_dependencies; printf SHOULD_NOT_CONTINUE",
            {"APT_FAIL_UPDATE": "9"},
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("E: fixture update failure", result.stdout)
        self.assertNotIn("SHOULD_NOT_CONTINUE", result.stdout)
        self.assertNotIn("[ERROR]", result.stdout)
        self.assertEqual(sum("update" in args for args in self.commands()), 3)
        self.assertFalse(any("install" in args for args in self.commands()))

    def test_package_install_failure_is_bounded_and_keeps_native_error(self):
        result = self.run_function(
            DEPENDENCY_AVAILABILITY + "ensure_dependencies; printf SHOULD_NOT_CONTINUE",
            {"APT_FAIL_INSTALL": "9"},
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("E: fixture install failure", result.stdout)
        self.assertNotIn("SHOULD_NOT_CONTINUE", result.stdout)
        self.assertEqual(sum("install" in args for args in self.commands()), 3)
        self.assertFalse(Path(self.environment["MOCK_DEPENDENCIES_READY"]).exists())

    def test_non_systemd_host_is_reported_without_installing_an_init_system(self):
        Path(self.environment["MOCK_DEPENDENCIES_READY"]).touch()
        self.stub("rpm", '#!/bin/sh\nprintf "package systemd is not installed\\n" >&2\nexit 1\n')
        result = self.run_function(DEPENDENCY_AVAILABILITY + "ensure_dependencies")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("package systemd is not installed", result.stdout)
        self.assertEqual(self.commands(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
