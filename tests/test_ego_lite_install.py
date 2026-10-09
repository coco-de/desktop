"""ego lite 설치: 멱등성·CPU별 dmg 선택·서명 검증·실패 시 계속 진행·정리·검증 줄·안내 번호를 검증한다.

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
SOURCE = SCRIPT.read_text(encoding='utf-8')


def install_block():
    start = SOURCE.index('EGO_LITE_APP=')
    marker = SOURCE.index('install_ego_lite() {', start)
    end = SOURCE.index('\n}', marker) + 2
    return SOURCE[start:end]


def verification_block():
    start = SOURCE.index("# ego lite: '설치됨'과 '에이전트에서 쓸 수 있음'이 다르다")
    end = SOURCE.index('\nfi\n', start) + 4
    return SOURCE[start:end]


BLOCK = install_block()
DMG_BASE = re.search(r'^EGO_LITE_DMG_BASE="([^"]+)"', BLOCK, re.M).group(1)
TEAM_ID = re.search(r'^EGO_LITE_TEAM_ID="([^"]+)"', BLOCK, re.M).group(1)

# 실제 명령의 동작을 흉내 낸다.
#  - hdiutil detach 는 마운트돼 있지 않으면 실패하고, 마운트돼 있으면 마운트 지점을 비운다(실제 해제처럼).
#    → 다운로드 실패처럼 마운트 전에 끝나는 경로에서도 정리(임시 폴더 삭제)가 끊기지 않는지 본다.
#  - codesign 은 `--verify -R=<요구사항>` 일 때 요구사항에 든 Team ID 를 STUB_TEAM_ID 와 비교해 3 을 돌려주고,
#    `-dv` 로 불리면 언제나 '진짜 팀' 줄이 섞인 출력을 낸다 — 출력 문자열을 믿는 구현은 속는다(스푸핑 재현).
STUBS = r'''
uname() { if [[ "${1:-}" == "-m" ]]; then printf '%s\n' "$STUB_UNAME_M"; else command uname "$@"; fi; }
sysctl() { printf '%s\n' "${STUB_SYSCTL_ARM64:-0}"; }
curl() {
  local out="" url="" prev="" a
  for a in "$@"; do
    if [[ "$prev" == "-o" ]]; then out="$a"; fi
    prev="$a"; url="$a"
  done
  printf 'curl %s\n' "$*" >> "$CALLS"
  if [[ "${STUB_CURL_FAIL:-0}" == 1 ]]; then return 22; fi
  printf 'FAKE-DMG' > "$out"
  if [[ "${STUB_CURL_CREATES_APP:-0}" == 1 ]]; then
    mkdir -p "$EGO_LITE_SYSTEM_APPS/ego lite.app" && printf 'mine' > "$EGO_LITE_SYSTEM_APPS/ego lite.app/MARKER"
  fi
}
hdiutil() {
  case "$1" in
    attach)
      printf 'attach %s\n' "$*" >> "$CALLS"
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
      rm -rf "$2"/.attached "$2"/*
      ;;
  esac
}
spctl()    { printf 'spctl\n' >> "$CALLS"; [[ "${STUB_SPCTL_FAIL:-0}" != 1 ]]; }
codesign() {
  printf 'codesign %s\n' "$*" >> "$CALLS"
  case " $* " in
    *" --verify "*)
      [[ "${STUB_SIGNATURE_BROKEN:-0}" != 1 ]] || return 1
      local ou; ou=$(printf '%s' "$*" | sed -n 's/.*subject\.OU\] = "\([^"]*\)".*/\1/p')
      [[ "$ou" == "${STUB_TEAM_ID:-JGQLC6YQYJ}" ]] || return 3
      ;;
    *) printf 'Identifier=x\nTeamIdentifier=JGQLC6YQYJ\n' >&2 ;;
  esac
}
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

    def assert_installed(self, where):
        self.assertTrue((where / APP / 'Contents' / 'Info.plist').is_file())
        self.assertEqual([p.name for p in where.glob('.ego-lite-install.*')], [])   # 임시 복사본이 남지 않는다

    def assert_not_installed(self, result):
        self.assertFalse((result.apps / APP).exists())
        self.assertFalse((result.home / 'Applications' / APP).exists())
        for folder in (result.apps, result.home / 'Applications'):                   # 반쯤 복사된 임시 폴더도 없다
            if folder.exists():
                self.assertEqual(os.listdir(folder), [])

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
                # 추적 코드(refcode)가 붙은 별칭이 아니라 토큰 없는 주소를 쓴다
                self.assertTrue(result.calls[0].endswith(f' {DMG_BASE}/{arch}/egolite.dmg'), result.calls[0])

    def test_install_verifies_before_copying_then_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            result = self.run_install(Path(temp), runs=2)
            self.assert_installed(result.apps)
            self.assertIn('설치 완료', result.out)
            self.assertIn('이미 존재', result.out)                       # 두 번째 실행은 아무것도 하지 않는다
            self.assertEqual(len([c for c in result.calls if c.startswith('curl')]), 1)
            for check in ('spctl', 'codesign --verify'):                 # 복사보다 검증이 먼저다
                position = next(i for i, c in enumerate(result.calls) if c.startswith(check))
                self.assertLess(position, result.calls.index('ditto'))
            self.assertIn('detach', result.calls)
            self.assert_continues_and_cleans_up(result)

    def test_download_and_mount_use_safe_flags(self):
        with tempfile.TemporaryDirectory() as temp:
            result = self.run_install(Path(temp))
            curl_call = next(c for c in result.calls if c.startswith('curl'))
            attach_call = next(c for c in result.calls if c.startswith('attach'))
            self.assertRegex(curl_call, r' -\S*f\S* ')                   # HTTP 오류를 성공으로 읽지 않는다(curl -f)
            self.assertTrue(DMG_BASE.startswith('https://'))             # 암호화된 연결
            for flag in ('-readonly', '-nobrowse'):                      # 내려받은 이미지는 읽기 전용으로만 연다
                self.assertIn(flag, attach_call)

    def test_signer_is_pinned_by_requirement_not_by_output_text(self):
        # 서명 식별자에 'TeamIdentifier=<진짜 팀>' 줄을 심은 가짜는 `codesign -dv` 출력으로는 진짜와 구분되지 않는다.
        # 그래서 요구사항 검사(codesign --verify -R=…)가 Team ID 를 직접 비교해야 하고, 고정값은 스크립트의 상수다.
        with tempfile.TemporaryDirectory() as temp:
            result = self.run_install(Path(temp), STUB_TEAM_ID='EVILTEAM00')
            self.assertIn('서명 검증 실패', result.out)
            self.assertIn(f'subject.OU] = "{TEAM_ID}"', next(c for c in result.calls if c.startswith('codesign')))
            self.assert_not_installed(result)

    def test_falls_back_to_home_applications_when_system_folder_is_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            result = self.run_install(Path(temp), create_apps=False)
            self.assert_installed(result.home / 'Applications')
            self.assertFalse(result.apps.exists())
            self.assert_continues_and_cleans_up(result)

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0, 'root 는 쓰기 불가 폴더에도 쓸 수 있다')
    def test_falls_back_to_home_applications_when_system_folder_is_not_writable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'apps').mkdir()
            (root / 'apps').chmod(0o555)
            try:
                result = self.run_install(root)
            finally:
                (root / 'apps').chmod(0o755)
            self.assert_installed(result.home / 'Applications')
            self.assertEqual(os.listdir(root / 'apps'), [])
            self.assert_continues_and_cleans_up(result)

    def test_app_installed_during_download_is_not_nested_or_overwritten(self):
        # 내려받는 사이 다른 곳에서 앱이 설치되면 mv 는 그 폴더 '안으로' 들어가 앱을 망가뜨린다 — 옮기기 직전에 다시 확인한다
        with tempfile.TemporaryDirectory() as temp:
            result = self.run_install(Path(temp), STUB_CURL_CREATES_APP=1)
            self.assertIn('이미 존재(내려받는 사이에 설치됨)', result.out)
            self.assertEqual(os.listdir(result.apps), [APP])
            self.assertEqual(os.listdir(result.apps / APP), ['MARKER'])  # 남이 설치한 앱은 그대로, 중첩도 없다
            self.assert_continues_and_cleans_up(result)

    def test_failures_warn_skip_and_clean_up_without_stopping_the_script(self):
        cases = (
            ('download fails', {'STUB_CURL_FAIL': 1}, '다운로드 실패', False),
            ('dmg cannot be opened', {'STUB_ATTACH_FAIL': 1}, '설치 파일을 열지 못함', False),
            ('app missing in dmg', {'STUB_DMG_EMPTY': 1}, '찾지 못함', False),
            ('not notarized', {'STUB_SPCTL_FAIL': 1}, '서명 검증 실패', False),
            ('other publisher', {'STUB_TEAM_ID': 'EVILTEAM00'}, '서명 검증 실패', False),
            ('signature broken', {'STUB_SIGNATURE_BROKEN': 1}, '서명 검증 실패', False),
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


class EgoLiteReportingTests(unittest.TestCase):
    """설치 검증 줄과 마지막 안내 — 사용자가 읽는 부분이라 따로 지킨다."""

    def run_verification(self, home):
        script = ('have() { command -v "$1" >/dev/null 2>&1; }\n' + verification_block())
        env = dict(os.environ, HOME=str(home), PATH='/usr/bin:/bin')     # 실제 ego-browser 가 PATH 에 있어도 영향 없게
        proc = subprocess.run(['bash', '-e'], input=script, text=True, env=env, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout

    def test_verification_line_reports_install_command_and_each_agent_separately(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            out = self.run_verification(home)
            self.assertIn('❌ (수동 설치', out)                                   # 미설치

            (home / 'Applications' / APP).mkdir(parents=True)
            out = self.run_verification(home)
            self.assertIn('첫 실행 전', out)                                      # 앱만 있고 아무것도 없음

            (home / '.local' / 'bin').mkdir(parents=True)
            (home / '.local' / 'bin' / 'ego-browser').write_text('#!/bin/sh\n')
            (home / '.local' / 'bin' / 'ego-browser').chmod(0o755)
            out = self.run_verification(home)
            self.assertIn('ego-browser 명령 ✓ · 에이전트 스킬 — Claude Code ❌ · Codex·OpenCode ❌', out)
            self.assertIn('↳ ❌는 ego lite가 아직 만들지 못한 것', out)

            (home / '.claude' / 'skills' / 'ego-browser').mkdir(parents=True)
            out = self.run_verification(home)
            self.assertIn('Claude Code ✓ · Codex·OpenCode ❌', out)

            (home / '.agents' / 'skills' / 'ego-browser').mkdir(parents=True)
            out = self.run_verification(home)
            self.assertIn('Claude Code ✓ · Codex·OpenCode ✓', out)
            self.assertNotIn('↳', out)                                           # 전부 정상이면 안내 줄이 없다

    def test_verification_line_does_not_say_first_run_when_only_the_command_is_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            (home / 'Applications' / APP).mkdir(parents=True)
            (home / '.claude' / 'skills' / 'ego-browser').mkdir(parents=True)
            out = self.run_verification(home)
            self.assertNotIn('첫 실행 전', out)
            self.assertIn('ego-browser 명령 ❌ · 에이전트 스킬 — Claude Code ✓', out)

    def test_final_guidance_numbers_are_unique_and_consecutive(self):
        tail = SOURCE[SOURCE.index('echo "✅ 완료! 다음 단계:"'):]
        numbers = [int(n) for n in re.findall(r'^echo "\s*(\d+)\. ', tail, re.M)]
        self.assertGreaterEqual(len(numbers), 12)
        self.assertEqual(numbers, list(range(1, len(numbers) + 1)))


if __name__ == '__main__':
    unittest.main()
