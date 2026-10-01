#!/usr/bin/env python3
"""실제 사용자 암호를 쓰지 않는 설정 계약·macOS 키체인 통합 테스트."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch


HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("keychain_setup", HERE / "setup.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def test_should_reject_ambiguous_keychain_paths(self):
        with self.assertRaises(RuntimeError):
            setup.resolve_keychain(["/one/laputa.keychain-db", "/two/laputa.keychain-db"], None, "laputa")
        self.assertEqual(setup.resolve_keychain(["/one/laputa.keychain-db"] * 2, None, "laputa"), "/one/laputa.keychain-db")

    def test_should_resolve_custom_name_when_explicit_path_is_supplied(self):
        self.assertEqual(setup.resolve_keychain(["/one/company-signing.keychain-db"], "/one/company-signing.keychain-db", "laputa"), "/one/company-signing.keychain-db")

    def test_should_keep_password_and_op_out_of_login_agent(self):
        data = plistlib.dumps(setup.agent_plist())
        agent = plistlib.loads(data)
        self.assertEqual(agent["ProgramArguments"], [str(setup.HELPER), "unlock-all", str(setup.CONFIG)])
        self.assertEqual(agent["LimitLoadToSessionType"], "Aqua")
        self.assertTrue(agent["RunAtLoad"])
        self.assertGreaterEqual(agent["StartInterval"], 60)
        self.assertNotIn(b"op://", data)
        self.assertNotIn("EnvironmentVariables", agent)
        self.assertNotIn("KeepAlive", agent)

    def test_should_parse_only_valid_identities_from_security_output(self):
        output = '  1) ' + 'A' * 40 + ' "Apple Development: Example"\n     1 valid identities found\n'
        with patch.object(setup, "run", return_value=Mock(stdout=output)) as command:
            self.assertEqual(setup.valid_identities("/a.keychain-db", "codesigning"), [{"sha1": "A" * 40, "name": "Apple Development: Example"}])
            self.assertIn("-v", command.call_args.args[0])

    def test_should_verify_installer_when_codesigning_policy_has_zero_identities(self):
        name = "Developer ID Installer: Example (TEAM)"
        identity = {"name": name, "sha1": "B" * 40}
        monitor = Mock()

        def command(args, **_kwargs):
            if args[1] == "identities":
                return Mock(stdout=json.dumps([identity]), stderr="", returncode=0)
            if args[0] == "/usr/sbin/pkgutil":
                return Mock(stdout="Status: signed by a certificate trusted by macOS\n1. " + name, stderr="", returncode=0)
            return Mock(stdout="", stderr="", returncode=0)

        def identities(_path, policy):
            return [identity] if policy == "basic" else []

        with patch.object(setup, "load_config", return_value={"targets": [{"path": "/fastlane.keychain-db"}]}), \
                patch.object(setup, "PromptMonitor", return_value=monitor), \
                patch.object(setup, "valid_identities", side_effect=identities), \
                patch.object(setup, "run", side_effect=command), contextlib.redirect_stdout(io.StringIO()) as output:
            setup.verify(None)
        result = json.loads(output.getvalue().splitlines()[-1])
        self.assertEqual(result["codesign_passed"], 0)
        self.assertEqual(result["productsign_passed"], 2)
        self.assertEqual(result["unavailable"], [])
        self.assertEqual(monitor.sign.call_count, 2)
        self.assertTrue(all(call.args[0][0] == "/usr/bin/productsign" for call in monitor.sign.call_args_list))

    def test_should_report_missing_private_key_pair_without_false_signing_success(self):
        with patch.object(setup, "load_config", return_value={"targets": [{"path": "/fastlane.keychain-db"}]}), \
                patch.object(setup, "PromptMonitor", return_value=Mock()), \
                patch.object(setup, "valid_identities", return_value=[]), \
                patch.object(setup, "run", return_value=Mock(stdout="[]", stderr="", returncode=0)), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            setup.verify(None)
        result = json.loads(output.getvalue().splitlines()[-1])
        self.assertEqual(result["codesign_passed"], 0)
        self.assertEqual(result["productsign_passed"], 0)
        self.assertEqual(result["unavailable"][0]["reason"], "서명용 인증서·개인 키 쌍 없음")

    def test_should_uninstall_idempotently_when_nothing_is_registered(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(setup, "ROOT", Path(directory) / "missing"), \
                patch.object(setup, "HELPER", Path(directory) / "missing/helper"), \
                patch.object(setup, "AGENT", Path(directory) / "missing.plist"), \
                patch.object(setup, "stop_agent"), patch.object(setup, "run") as run, \
                contextlib.redirect_stdout(io.StringIO()):
            setup.uninstall(None)
            setup.uninstall(None)
            run.assert_not_called()

    def test_should_fail_status_when_inspection_succeeds_but_settings_have_drifted(self):
        baseline = {"no_timeout": True, "lock_on_sleep": False,
                    "signing_keys": [{"has_partition": True, "acl": [
                        {"type": "sign", "all_applications": False, "requires_password": False, "missing_tools": []},
                        {"type": "partition", "missing_partitions": []}]}]}
        reports = [dict(baseline, no_timeout=False), dict(baseline, lock_on_sleep=True),
                   dict(baseline, signing_keys=[{"has_partition": False, "acl": []}]),
                   dict(baseline, signing_keys=[{"has_partition": True, "acl": [{"type": "sign", "missing_tools": ["/usr/bin/codesign"]}]}]),
                   dict(baseline, signing_keys=[{"has_partition": True, "acl": [{"type": "partition", "missing_partitions": ["codesign:"]}]}]),
                   dict(baseline, signing_keys=[{"has_partition": True, "acl": [{"type": "sign", "all_applications": True}]}]),
                   dict(baseline, signing_keys=[{"has_partition": True, "acl": [{"type": "sign", "requires_password": True}]}])]
        for report in reports:
            with self.subTest(report=report):
                def command(args, **_kwargs):
                    return Mock(returncode=0, stderr="", stdout=json.dumps(report) if args[1] == "inspect" else "{}")
                with patch.object(setup, "load_config", return_value={"targets": [{"path": "/laputa.keychain-db"}]}), \
                        patch.object(setup, "run", side_effect=command), contextlib.redirect_stdout(io.StringIO()), \
                        self.assertRaises(RuntimeError):
                    setup.status(None)

    def test_should_dispatch_keychain_help_without_running_full_setup(self):
        result = subprocess.run(["/bin/bash", HERE.parent / "mac-setup.sh", "--keychains-only", "--help"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        self.assertIn("--laputa-ref", result.stdout)
        self.assertNotIn("Homebrew 설치", result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "Security.framework는 macOS 전용")
    def test_should_enforce_real_cache_acl_and_preserve_signing_partitions(self):
        with tempfile.TemporaryDirectory(prefix="desktop-keychain-tests-") as directory:
            directory = Path(directory)
            helper, fixture = directory / "helper", directory / "fixture"
            common = ["/usr/bin/xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror", "-Wno-deprecated-declarations", "-framework", "Foundation", "-framework", "Security"]
            subprocess.run(common + [HERE / "helper.m", "-o", helper], check=True, timeout=30)
            subprocess.run(common + [HERE / "test-helper.m", "-o", fixture], check=True, timeout=30)
            # ad-hoc은 인증서·개인 키를 사용하지 않는다. 테스트는 사용자의 서명 자산에 의존하지 않는다.
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", helper, fixture], check=True, capture_output=True, timeout=10)
            subprocess.run([fixture, helper, directory], check=True, timeout=45)


if __name__ == "__main__":
    unittest.main(verbosity=2)
