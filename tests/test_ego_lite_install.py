"""ego lite 설치 함수: 멱등성·CPU별 dmg 선택·서명 검증·실패 시 계속 진행·정리를 검증한다.

mac-setup.sh 의 설치 블록(상수 + install_ego_lite)을 그대로 잘라 `bash -e`(실제 스크립트와 같은 조건)로
실행하고, 맥 전용 외부 명령(uname·sysctl·curl·hdiutil·spctl·codesign·ditto)만 bash 함수로 대체한다.
그래서 맥이 아닌 CI(ubuntu)에서도 돈다.
"""
import os
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'macos/mac-setup.sh'
APP = 'ego lite.app'


def install_block():
    source = SCRIPT.read_text(encoding='utf-8')
    start = source.index('EGO_LITE_APP=')
    marker = source.index('install_ego_lite() {', start)
    end = source.index('\n}', marker) + 2
    return source[start:end]


BLOCK = install_block()
DMG_BASE = re.search(r'^EGO_LITE_DMG_BASE="([^"]+)"', BLOCK, re.M).group(1)
DMG_TOKEN = re.search(r'^EGO_LITE_DMG_TOKEN="([^"]+)"', BLOCK, re.M).group(1)

# 실제 명령의 동작을 흉내 낸다. 특히 hdiutil detach 는 마운트돼 있지 않으면 실패한다 —
# 다운로드 실패처럼 마운트 전에 끝나는 경로에서도 정리(임시 폴더 삭제)가 끊기지 않는지 보기 위함이다.
STUBS = r'''
uname() { if [[ "${1:-}" == "-m" ]]; then printf '%s\n' "$STUB_UNAME_M"; else command uname "$@"; fi; }
sysctl() { printf '%s\n' "${STUB_SYSCTL_ARM64:-0}"; }
curl() {
  local out="" url="" prev="" a
  for a in "$@"; do
    if [[ "$prev" == "-o" ]]; then out="$a"; fi
    prev="$a"; url="$a"
  done
  printf 'curl %s\n' "$url" >> "$CALLS"
  if [[ "${STUB_CURL_FAIL:-0}" == 1 ]]; then return 22; fi
  printf 'FAKE-DMG' > "$out"
}
hdiutil() {
  case "$1" in
    attach)
      printf 'attach\n' >> "$CALLS"
      if [[ "${STUB_ATTACH_FAIL:-0}" == 1 ]]; then return 1; fi
      local mp="" prev="" a
      for a in "$@"; do
        if [[ "$prev" == "-mountpoint" ]]; then mp="$a"; fi
        prev="$a"
      done
      if [[ "${STUB_DMG_EMPTY:-0}" != 1 ]]; then
        mkdir -p "$mp/ego lite.app/Contents" && printf 'plist' > "$mp/ego lite.app/Contents/Info.plist"
      fi
      : > "$mp/.attached"
      ;;
    detach)
      printf 'detach\n' >> "$CALLS"
      [[ -e "$2/.attached" ]] || return 1
      rm -f "$2/.attached"
      ;;
  esac
}
spctl()    { printf 'spctl\n' >> "$CALLS"; [[ "${STUB_SPCTL_FAIL:-0}" != 1 ]]; }
codesign() { printf 'codesign\n' >> "$CALLS"; printf 'TeamIdentifier=%s\n' "${STUB_TEAM_ID:-JGQLC6YQYJ}" >&2; }
ditto()    { printf 'ditto\n' >> "$CALLS"; if [[ "${STUB_DITTO_FAIL:-0}" == 1 ]]; then return 1; fi; cp -R "$1" "$2"; }
'''


class EgoLiteInstallTests(unittest.TestCase):
    def run_install(self, root, runs=1, create_apps=True, **stub_env):
        home, apps, tmp, calls = root / 'home', root / 'apps', root / 'tmp', root / 'calls.log'
        home.mkdir(exist_ok=True)
        tmp.mkdir(exist_ok=True)
        if create_apps:
            apps.mkdir(exist_ok=True)
        script = (STUBS + BLOCK + f'\nEGO_LITE_SYSTEM_APPS={shlex.quote(str(apps))}\n'
                  + 'install_ego_lite\necho "RC=$?"\n' * runs + 'echo AFTER\n')
        env = dict(os.environ, HOME=str(home), TMPDIR=str(tmp), CALLS=str(calls), STUB_UNAME_M='arm64')
        env.update({key: str(value) for key, value in stub_env.items()})
        proc = subprocess.run(['bash', '-e'], input=script, text=True, env=env, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return SimpleNamespace(
            out=proc.stdout, home=home, apps=apps, tmp=tmp,
            calls=calls.read_text().splitlines() if calls.exists() else [],
        )

    def assert_installed(self, result, where):
        self.assertTrue((where / APP / 'Contents' / 'Info.plist').is_file())
        self.assertFalse((result.tmp / 'stage').exists())

    def assert_not_installed(self, result):
        self.assertFalse((result.apps / APP).exists())
        self.assertFalse((result.home / 'Applications' / APP).exists())

    def assert_continues_and_cleans_up(self, result):
        # bash -e 아래에서도 함수가 스크립트를 멈추지 않고, 임시 폴더·마운트 흔적을 남기지 않는다
        self.assertIn('RC=0', result.out)
        self.assertIn('AFTER', result.out)
        self.assertEqual(os.listdir(result.tmp), [])

    def test_already_installed_skips_download(self):
        for label, prepare in (
            ('system', lambda r: (r / 'apps' / APP).mkdir(parents=True)),
            ('home', lambda r: (r / 'home' / 'Applications' / APP).mkdir(parents=True)),
        ):
            with self.subTest(location=label), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                prepare(root)
                (root / 'apps').mkdir(exist_ok=True)
                result = self.run_install(root)
                self.assertIn('이미 존재', result.out)
                self.assertEqual(result.calls, [])
                self.assert_continues_and_cleans_up(result)

    def test_dmg_matches_cpu_including_rosetta_terminal(self):
        cases = (('arm64', '0', 'arm64'), ('x86_64', '0', 'x64'), ('x86_64', '1', 'arm64'))
        for uname_m, sysctl_arm64, arch in cases:
            with self.subTest(uname=uname_m, sysctl=sysctl_arm64), tempfile.TemporaryDirectory() as temp:
                result = self.run_install(Path(temp), STUB_UNAME_M=uname_m, STUB_SYSCTL_ARM64=sysctl_arm64, STUB_CURL_FAIL=1)
                self.assertEqual(result.calls[0], f'curl {DMG_BASE}/{arch}/egolite-{DMG_TOKEN}.dmg')

    def test_install_verifies_before_copying_then_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = self.run_install(root, runs=2)
            self.assert_installed(result, result.apps)
            self.assertIn('설치 완료', result.out)
            self.assertIn('이미 존재', result.out)                       # 두 번째 실행은 아무것도 하지 않는다
            self.assertEqual(len([c for c in result.calls if c.startswith('curl')]), 1)
            for check in ('spctl', 'codesign'):                          # 복사보다 검증이 먼저다
                self.assertLess(result.calls.index(check), result.calls.index('ditto'))
            self.assertIn('detach', result.calls)
            self.assert_continues_and_cleans_up(result)

    def test_falls_back_to_home_applications_when_system_folder_is_not_writable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = self.run_install(root, create_apps=False)
            self.assert_installed(result, result.home / 'Applications')
            self.assertFalse(result.apps.exists())
            self.assert_continues_and_cleans_up(result)

    def test_failures_warn_skip_and_clean_up_without_stopping_the_script(self):
        cases = (
            ('download fails', {'STUB_CURL_FAIL': 1}, '다운로드 실패', False),
            ('dmg cannot be opened', {'STUB_ATTACH_FAIL': 1}, '설치 파일을 열지 못함', False),
            ('app missing in dmg', {'STUB_DMG_EMPTY': 1}, '찾지 못함', False),
            ('not notarized', {'STUB_SPCTL_FAIL': 1}, '서명 검증 실패', False),
            ('other publisher', {'STUB_TEAM_ID': 'EVILTEAM00'}, '서명 검증 실패', False),
            ('copy fails', {'STUB_DITTO_FAIL': 1}, '복사 실패', True),
        )
        for label, stub_env, message, copy_attempted in cases:
            with self.subTest(case=label), tempfile.TemporaryDirectory() as temp:
                result = self.run_install(Path(temp), **stub_env)
                self.assertIn(message, result.out)
                self.assertIn('https://lite.ego.app/ko', result.out)     # 수동 설치 안내가 항상 붙는다
                self.assertEqual('ditto' in result.calls, copy_attempted)  # 검증 실패면 복사 자체를 시도하지 않는다
                self.assert_not_installed(result)
                self.assert_continues_and_cleans_up(result)


if __name__ == '__main__':
    unittest.main()
