"""조직 키의 실제 셸 주입 코드: 멱등성·조직 격리·부분 실패·비밀 비출력을 검증한다."""
import base64
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = [ROOT / 'macos/mac-setup.sh', ROOT / 'linux/linux-setup.sh']
VALUES = {
    'COCODE_ASC_KEY_ID': 'TESTKEY123',
    'COCODE_ASC_ISSUER_ID': '1f078b74-be9f-4985-a055-aa7881dc293a',
    'COCODE_ASC_PRIVATE_KEY_BASE64': base64.b64encode(b'SYNTHETIC_PRIVATE_KEY_NOT_A_REAL_CREDENTIAL').decode(),
    'COCODE_APPLE_TEAM_ID': 'DNNK8RH9GY',
}


class CocodeAscEnvTests(unittest.TestCase):
    def run_injection(self, script, home, missing='', team='DNNK8RH9GY', issuer=VALUES['COCODE_ASC_ISSUER_ID']):
        source = script.read_text()
        start = source.index('inject_cocode_asc_key() {')
        end = source.index('\n}', start) + 2
        function = source[start:end]
        stubs = '''
op_has_account() { return 0; }
TEAM_OP_ACCOUNT=team-cocodeinc.1password.com
COCODE_ASC_OP_REF='op://API Token/Cocode App Store Connect API'
op() {
  [[ "$1" == read && "$2" == --account && "$3" == "$TEAM_OP_ACCOUNT" ]] || return 2
  local field="${4##*/}"
  [[ "$field" != "$TEST_MISSING" ]] || return 1
  case "$field" in
    key_id) printf '%s' "$TEST_KEY_ID" ;;
    issuer_id) printf '%s' "$TEST_ISSUER" ;;
    credential) printf '%s' "$TEST_PRIVATE_KEY" ;;
    team_id) printf '%s' "$TEST_TEAM" ;;
    *) return 1 ;;
  esac
}
'''
        env = dict(os.environ, HOME=str(home), TEST_MISSING=missing, TEST_TEAM=team,
                   TEST_ISSUER=issuer, TEST_KEY_ID=VALUES['COCODE_ASC_KEY_ID'],
                   TEST_PRIVATE_KEY=VALUES['COCODE_ASC_PRIVATE_KEY_BASE64'])
        result = subprocess.run(['bash', '-e'], input=stubs + function + '\nif inject_cocode_asc_key; then printf success; else printf skipped; fi',
                                text=True, env=env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(VALUES['COCODE_ASC_PRIVATE_KEY_BASE64'], result.stdout + result.stderr)
        return result.stdout

    def test_success_repeat_and_unrelated_organization_preserved(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                config = home / '.zshrc'
                original = 'export ASC_KEY_ID=LAPUTA_KEY\nexport USER_SETTING=keep\n'
                config.write_text(original)
                self.assertEqual(self.run_injection(script, home), 'success')
                first = config.read_text()
                self.assertTrue(first.startswith(original))
                for name, value in VALUES.items():
                    self.assertEqual(first.count(f'export {name}={value}\n'), 1)
                self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                self.assertEqual(self.run_injection(script, home), 'success')
                self.assertEqual(config.read_text(), first)

    def test_missing_field_preserves_all_previous_values(self):
        for script in SCRIPTS:
            for field in ('key_id', 'issuer_id', 'credential', 'team_id'):
                with self.subTest(script=script, missing=field), tempfile.TemporaryDirectory() as temp:
                    home = Path(temp)
                    config = home / '.zshrc'
                    previous = ''.join(f'export {name}=previous_value\n' for name in VALUES)
                    config.write_text(previous)
                    self.assertEqual(self.run_injection(script, home, missing=field), 'skipped')
                    self.assertEqual(config.read_text(), previous)
                    self.assertEqual(list(home.glob('.zshrc.asc.*')), [])

    def test_other_organization_or_issuer_cannot_replace_cocode_key(self):
        for script in SCRIPTS:
            for mismatch in ({'team': 'OTHERTEAM1'}, {'issuer': 'other-organization'}):
                with self.subTest(script=script, mismatch=mismatch), tempfile.TemporaryDirectory() as temp:
                    home = Path(temp)
                    config = home / '.zshrc'
                    previous = 'export COCODE_ASC_KEY_ID=previous_key\n'
                    config.write_text(previous)
                    self.assertEqual(self.run_injection(script, home, **mismatch), 'skipped')
                    self.assertEqual(config.read_text(), previous)

    def test_summary_and_full_verification_report_present_keys_without_grep_errors(self):
        self.check_status_output(present=True)

    def test_summary_and_full_verification_report_missing_keys_without_grep_errors(self):
        self.check_status_output(present=False)

    def check_status_output(self, present):
        # 실제 --env-only 요약·전체 검증의 두 루프를 실행한다. 값을 출력하지 않아야 한다.
        for script in SCRIPTS:
            loops = list(re.finditer(
                r'(?m)^[ \t]*for asc_var in COCODE_ASC_KEY_ID[^\n]*; do\n[\s\S]*?^[ \t]*done$',
                script.read_text()))
            self.assertEqual(len(loops), 2, f'{script}: 요약·전체 검증 루프가 필요합니다')
            for index, loop in enumerate(loops):
                with self.subTest(script=script, loop=index, present=present), tempfile.TemporaryDirectory(prefix='ASC home ') as temp:
                    home = Path(temp)
                    config = ''.join(f'export {name}={value}\n' for name, value in VALUES.items()) if present else '# 키 미설정\n'
                    (home / '.zshrc').write_text(config)
                    result = subprocess.run(['bash', '-e'], input=loop.group(),
                                            env=dict(os.environ, HOME=str(home)), text=True,
                                            capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr, '')
                    expected = '✓ 주입됨' if present else '❌ 미주입'
                    for name in VALUES:
                        self.assertIn(f'{name}: {expected}', result.stdout)
                    self.assertNotIn(VALUES['COCODE_ASC_PRIVATE_KEY_BASE64'], result.stdout)


if __name__ == '__main__':
    unittest.main()
