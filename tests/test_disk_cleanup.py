"""디스크 자동 정리(macos/disk-cleanup) 회귀 검사.

임시 HOME · 임시 폴더에 실제 폴더를 만들고 수정 시각을 바꿔 가며, 스크립트가 '쓰는 중이거나
최근에 바뀐 것은 남기고, 오래 쓰지 않은 것만 지우는지'를 확인한다. Docker 정리는 docker·colima 를
가짜 명령으로 바꿔 끼워 어떤 명령을 어떤 인자로 부르는지만 본다 — 진짜 Docker 는 건드리지 않는다.
"""
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLEANUP = ROOT / 'macos/disk-cleanup'
SETUP = ROOT / 'macos/mac-setup.sh'
JOBS = {
    'dart-tmp-cleanup': ('cleanup-dart-tmp.sh', 900),
    'runner-cache-cleanup': ('cleanup-runner-cache.sh', 86400),
    'docker-disk-cleanup': ('cleanup-docker-disk.sh', 86400),
}
MINUTE = 60
HOUR = 3600
DAY = 24 * HOUR


def set_age(path, age_s):
    """path 아래 모든 항목의 수정 시각을 age_s 초 전으로 맞춘다 (폴더는 자식을 다 맞춘 뒤에)."""
    t = time.time() - age_s
    for dirpath, _, filenames in os.walk(path, topdown=False):
        for name in filenames:
            os.utime(os.path.join(dirpath, name), (t, t))
        os.utime(dirpath, (t, t))


def make_tree(path, age_s):
    """파일 두 개짜리 폴더를 만들고 전부 age_s 초 전에 바뀐 것으로 만든다."""
    (path / 'sub').mkdir(parents=True, exist_ok=True)
    (path / 'a.bin').write_bytes(b'x' * 4096)
    (path / 'sub' / 'b.bin').write_bytes(b'y' * 4096)
    set_age(path, age_s)


def touch_now(file_path):
    """파일 하나만 방금 바뀐 것으로 — 부모 폴더의 수정 시각은 그대로 남는다."""
    now = time.time()
    os.utime(file_path, (now, now))


def hold(*args):
    """명령줄에 args 를 가진 채 기다리는 프로세스 — '누가 쓰는 중' 을 흉내 낸다."""
    return subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)', *map(str, args)])


def hold_open(file_path):
    """file_path 를 열어 둔 채 기다리는 프로세스 (명령줄에는 경로가 없다)."""
    code = 'import sys, time; f = open(sys.stdin.readline().strip()); print("open", flush=True); time.sleep(120)'
    proc = subprocess.Popen([sys.executable, '-c', code], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    proc.stdin.write(f'{file_path}\n')
    proc.stdin.flush()
    proc.stdout.readline()
    return proc


def stop(*procs):
    for proc in procs:
        proc.kill()
        proc.wait()
        for stream in (proc.stdin, proc.stdout):
            if stream:
                stream.close()


class DartTmpCleanupTests(unittest.TestCase):
    def run_script(self, tmp_root, home, extra_env=None):
        env = dict(os.environ, HOME=str(home), CLEANUP_TMP_DIR=str(tmp_root), **(extra_env or {}))
        return subprocess.run(['sh', str(CLEANUP / 'cleanup-dart-tmp.sh')], env=env,
                              capture_output=True, text=True, timeout=120)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'T'
        self.home = Path(self.temp.name) / 'home'
        self.root.mkdir()
        self.home.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def test_age_guard_keeps_recent_and_removes_idle(self):
        """예전 판은 기준 시각을 'T' 로 이어 적어 macOS find 가 다른 시각으로 읽었고, 이 검사에서 5분 전 폴더를 지웠다."""
        make_tree(self.root / 'dart_test.kernel.fresh', 5 * MINUTE)    # 70분 미만 → 남김
        make_tree(self.root / 'dart_test.kernel.idle', 2 * HOUR)       # 70분 초과 → 지움
        make_tree(self.root / 'flutter_tools.recent', 2 * HOUR)        # 6시간 미만 → 남김
        make_tree(self.root / 'flutter_tools.idle', 7 * HOUR)          # 6시간 초과 → 지움
        make_tree(self.root / 'unrelated.cache', 30 * DAY)             # 대상 아님 → 남김
        inside = self.root / 'dart_test.kernel.inside'                 # 맨 위는 오래됐지만 안쪽이 방금 바뀜 → 남김
        make_tree(inside, 3 * HOUR)
        touch_now(inside / 'sub' / 'b.bin')

        result = self.run_script(self.root, self.home)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ['dart_test.kernel.fresh', 'dart_test.kernel.inside',
                          'flutter_tools.recent', 'unrelated.cache'])
        self.assertIn('회수', result.stdout)

    def test_still_cleans_when_temp_files_cannot_be_created(self):
        """디스크가 꽉 차 임시 파일을 못 만들어도 정리해야 한다 — 예전 판은 그 회차를 통째로 건너뛰었다."""
        make_tree(self.root / 'dart_test.kernel.idle', 2 * HOUR)

        result = self.run_script(self.root, self.home, {'TMPDIR': str(Path(self.temp.name) / 'no-such-dir')})

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'dart_test.kernel.idle').exists())

    def test_in_use_and_owner_running_are_kept(self):
        make_tree(self.root / 'dart_test.kernel.busy', 3 * HOUR)       # 명령줄이 가리킴 → 남김
        owned = self.root / 'dart_test.kernel.owned'                   # 만든 러너에서 dart test 실행 중 → 남김
        make_tree(owned, 3 * HOUR)
        (owned / 'test.dart').write_text("import '/Users/x/actions/runner-zeta/_work/app/app/test/a_test.dart';\n")
        set_age(owned, 3 * HOUR)
        make_tree(self.root / 'dart_test.kernel.orphan', 3 * HOUR)     # 아무도 안 씀 → 지움
        procs = [hold(self.root / 'dart_test.kernel.busy'), hold('actions/runner-zeta', 'dart', 'test')]
        try:
            result = self.run_script(self.root, self.home)
        finally:
            stop(*procs)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ['dart_test.kernel.busy', 'dart_test.kernel.owned'])


class RunnerCacheCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name) / 'home'
        idle, mid, old = 100 * HOUR, 5 * DAY, 20 * DAY
        actions = self.home / 'actions'
        runner = actions / 'runA'
        (runner / '_work').mkdir(parents=True)
        (runner / '.runner').write_text('{}')
        xcode = self.home / 'Library/Developer/Xcode'

        self.removed = [
            self.home / '.pub-cache-runA',
            self.home / '.gradle-runA',
            actions / '_cache637' / 'pub-runA',
            xcode / 'DerivedData-runA',
            xcode / 'Archives-runA.xcarchive',
            runner / '_work' / 'repoOld',                       # 14일 넘게 안 씀
        ]
        self.kept = [
            self.home / '.pub-cache-shared',                    # 여러 러너가 함께 씀
            actions / '_cache637' / 'pub-shared',
            actions / '_cache637' / 'gradle',                   # 러너별 사본이 아님
            xcode / 'DerivedData',                              # 개인 Xcode 캐시
            xcode / 'DerivedData-notarunner',                   # 러너 이름이 아님
            runner / '_work' / 'repoMid',                       # 5일 — 작업 폴더는 14일 기준
            runner / '_work' / '_tool',                         # 러너 내부 폴더
            actions / 'notarunner' / '_work' / 'repoOld',       # .runner 가 없는 폴더
        ]
        for path in self.removed + self.kept:
            make_tree(path, old if '_work' in str(path) else idle)
        set_age(runner / '_work' / 'repoMid', mid)

        # 맨 위 폴더는 오래됐지만 안쪽은 방금 쓴 캐시 — 예전 판은 맨 위 시각만 보고 지웠다
        self.inside = self.home / '.pub-cache-runB'
        make_tree(self.inside, idle)
        touch_now(self.inside / 'sub' / 'b.bin')
        self.active_checkout = runner / '_work' / 'repoActive'
        make_tree(self.active_checkout, old)
        touch_now(self.active_checkout / 'a.bin')

        self.busy_cmdline = self.home / '.pub-cache-runC'       # 명령줄이 가리킴
        make_tree(self.busy_cmdline, idle)
        self.busy_open = self.home / '.gradle-runD'             # 안의 파일이 열려 있음
        make_tree(self.busy_open, idle)

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, dry=False):
        env = dict(os.environ, HOME=str(self.home))
        if dry:
            env['DRY_RUN'] = '1'
        return subprocess.run(['sh', str(CLEANUP / 'cleanup-runner-cache.sh')], env=env,
                              capture_output=True, text=True, timeout=300)

    def test_removes_only_idle_runner_copies(self):
        procs = [hold(self.busy_cmdline), hold_open(self.busy_open / 'sub' / 'b.bin')]
        try:
            result = self.run_script()
        finally:
            stop(*procs)

        self.assertEqual(result.returncode, 0, result.stderr)
        for path in self.removed:
            self.assertFalse(path.exists(), f'지워야 함: {path.relative_to(self.home)}')
        for path in self.kept + [self.inside, self.active_checkout, self.busy_cmdline]:
            self.assertTrue(path.exists(), f'남겨야 함: {path.relative_to(self.home)}')
        if shutil.which('lsof'):
            self.assertTrue(self.busy_open.exists(), '열린 파일이 있는 캐시는 남겨야 함')
        self.assertIn('회수', result.stdout)

    def test_dry_run_lists_without_deleting(self):
        result = self.run_script(dry=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        for path in self.removed:
            self.assertTrue(path.exists())
            self.assertIn(f'[dry] {path.relative_to(self.home)}', result.stdout)
        self.assertNotIn('pub-cache-runB', result.stdout)
        self.assertNotIn('회수', result.stdout)


STUB_DOCKER = r'''#!/bin/sh
echo "docker $*" >> "$STUB_LOG"
case "$1 $2" in
  "volume ls") cat "$STUB_VOLUMES" ;;
  "volume inspect") awk -v n="$5" '$1 == n { print $2 }' "$STUB_VOLUMES_CREATED" ;;
esac
exit 0
'''
STUB_COLIMA = r'''#!/bin/sh
echo "colima $*" >> "$STUB_LOG"
[ "$1" = status ] && exit "${STUB_COLIMA_STATUS:-0}"
exit 0
'''


class DockerDiskCleanupTests(unittest.TestCase):
    OLD = 'a' * 64
    NEW = 'b' * 64
    OLD_WITH_OFFSET = 'c' * 64

    def run_script(self, colima_status=0, dry=False):
        temp = Path(self.temp.name)
        now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        volumes = {
            self.OLD: '2026-01-01T00:00:00Z',
            self.NEW: now,                                       # 72시간 안 → 남김
            self.OLD_WITH_OFFSET: '2026-01-01T09:00:00+09:00',
            'pgdata': '2026-01-01T00:00:00Z',                    # 이름 붙은 볼륨 → 남김
            'deadbeef': '2026-01-01T00:00:00Z',                  # 64자리가 아님 → 남김
        }
        (temp / 'volumes').write_text(''.join(f'{name}\n' for name in volumes))
        (temp / 'created').write_text(''.join(f'{name} {at}\n' for name, at in volumes.items()))
        env = {
            'HOME': str(temp / 'home'),
            'PATH': f'{self.bin}:/usr/bin:/bin',                 # 진짜 docker·colima 가 섞이지 않게
            'STUB_LOG': str(self.log),
            'STUB_VOLUMES': str(temp / 'volumes'),
            'STUB_VOLUMES_CREATED': str(temp / 'created'),
            'STUB_COLIMA_STATUS': str(colima_status),
        }
        if dry:
            env['DRY_RUN'] = '1'
        result = subprocess.run(['sh', str(CLEANUP / 'cleanup-docker-disk.sh')], env=env,
                                capture_output=True, text=True, timeout=120)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return result, calls

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.bin = Path(self.temp.name) / 'bin'
        self.bin.mkdir()
        (Path(self.temp.name) / 'home').mkdir()
        self.log = Path(self.temp.name) / 'calls.log'
        for name, body in (('docker', STUB_DOCKER), ('colima', STUB_COLIMA)):
            (self.bin / name).write_text(body)
            (self.bin / name).chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def test_prunes_old_anonymous_volumes_build_cache_and_trims(self):
        result, calls = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        removed = sorted(c.split()[-1] for c in calls if c.startswith('docker volume rm'))
        self.assertEqual(removed, [self.OLD, self.OLD_WITH_OFFSET])
        self.assertIn('docker builder prune -af --filter until=72h', calls)
        self.assertIn('colima ssh -- sudo fstrim -a', calls)
        self.assertIn('익명 볼륨 2개 정리', result.stdout)
        # 이미지 · 컨테이너 · 네트워크 · 일괄 prune 은 절대 부르지 않는다
        forbidden = [c for c in calls if re.search(r'\b(image|container|network|system)\b|volume prune', c)]
        self.assertEqual(forbidden, [])

    def test_does_nothing_when_colima_is_off(self):
        result, calls = self.run_script(colima_status=1)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['colima status'])

    def test_dry_run_changes_nothing(self):
        result, calls = self.run_script(dry=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        changing = [c for c in calls if c.startswith(('docker volume rm', 'docker builder', 'colima ssh'))]
        self.assertEqual(changing, [])
        self.assertIn(f'[dry] docker volume rm {self.OLD}', result.stdout)
        self.assertNotIn(self.NEW, result.stdout)


class LaunchdJobTests(unittest.TestCase):
    def test_plists_point_at_installed_scripts(self):
        for job, (script, interval) in JOBS.items():
            with self.subTest(job=job):
                data = plistlib.loads((CLEANUP / f'im.cocode.{job}.plist').read_bytes())
                self.assertEqual(data['Label'], f'im.cocode.{job}')
                self.assertEqual(data['ProgramArguments'][:2], ['/bin/sh', '-c'])
                self.assertEqual(data['ProgramArguments'][2],
                                 f'$HOME/.local/bin/{script} >> $HOME/Library/Logs/{job}.log 2>&1')
                self.assertEqual(data['StartInterval'], interval)
                self.assertFalse(data['RunAtLoad'])
                self.assertTrue(os.access(CLEANUP / script, os.X_OK), f'{script} 실행 권한')

    def test_scripts_are_posix_sh_with_lf(self):
        for script, _ in JOBS.values():
            with self.subTest(script=script):
                body = (CLEANUP / script).read_bytes()
                self.assertTrue(body.startswith(b'#!/bin/sh\n'))
                self.assertNotIn(b'\r\n', body)
                result = subprocess.run(['sh', '-n', str(CLEANUP / script)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)


class SetupScriptWiringTests(unittest.TestCase):
    """mac-setup.sh 의 9.5단계 본체를 떼어 내 가짜 launchctl·curl 로 돌린다."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name) / 'home'
        self.home.mkdir()
        self.log = Path(self.temp.name) / 'calls.log'
        self.loaded = Path(self.temp.name) / 'loaded'
        source = SETUP.read_text()
        jobs = re.search(r'^DISK_CLEANUP_JOBS=.*$', source, re.M).group(0)
        bodies = []
        for name in ('install_disk_cleanup', 'disk_cleanup_status'):
            start = source.index(f'{name}() {{')
            bodies.append(source[start:source.index('\n}', start) + 2])
        self.functions = jobs + '\n' + '\n'.join(bodies)

    def tearDown(self):
        self.temp.cleanup()

    def run_install(self, script_dir, curl_ok=True, command='install_disk_cleanup'):
        stubs = r'''
log() { echo "▶ $1"; }
launchctl() {
  echo "launchctl $*" >> "$STUB_LOG"
  case "$1" in
    print) grep -qxF "${2##*/}" "$STUB_LOADED" 2>/dev/null ;;
    bootstrap) p="${3##*/}"; echo "${p%.plist}" >> "$STUB_LOADED" ;;
    bootout) [ -f "$STUB_LOADED" ] && grep -vxF "${2##*/}" "$STUB_LOADED" > "$STUB_LOADED.new"; mv -f "$STUB_LOADED.new" "$STUB_LOADED" 2>/dev/null; return 0 ;;
  esac
}
curl() {
  [ "$STUB_CURL_OK" = 1 ] || return 22
  cp "$STUB_REPO/${2##*/}" "$4"
}
'''
        env = dict(os.environ, HOME=str(self.home), STUB_LOG=str(self.log), STUB_LOADED=str(self.loaded),
                   STUB_REPO=str(CLEANUP), STUB_CURL_OK='1' if curl_ok else '0')
        program = (stubs + f'SCRIPT_DIR="{script_dir}"\nREPO_RAW_BASE=https://example.invalid/macos\n'
                   + self.functions + f'\n{command}\n')
        result = subprocess.run(['bash', '-e'], input=program, text=True, env=env,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        self.log.unlink(missing_ok=True)
        return result.stdout, calls

    def bootstraps(self, calls):
        return sorted(c.split()[-1].rsplit('/', 1)[-1] for c in calls if c.startswith('launchctl bootstrap'))

    def test_install_is_idempotent_and_reloads_only_changed_jobs(self):
        out, calls = self.run_install(ROOT / 'macos')
        self.assertEqual(self.bootstraps(calls), sorted(f'im.cocode.{job}.plist' for job in JOBS))
        for job, (script, _) in JOBS.items():
            installed = self.home / '.local/bin' / script
            self.assertEqual(installed.read_bytes(), (CLEANUP / script).read_bytes())
            self.assertTrue(os.access(installed, os.X_OK))
            self.assertEqual((self.home / f'Library/LaunchAgents/im.cocode.{job}.plist').read_bytes(),
                             (CLEANUP / f'im.cocode.{job}.plist').read_bytes())
            self.assertIn(f'✓ im.cocode.{job} 등록', out)

        out, calls = self.run_install(ROOT / 'macos')
        self.assertEqual(self.bootstraps(calls), [])
        self.assertEqual(out.count('이미 최신으로 등록됨'), 3)

        (self.home / '.local/bin/cleanup-docker-disk.sh').write_text('#!/bin/sh\nexit 0\n')
        out, calls = self.run_install(ROOT / 'macos')
        self.assertEqual(self.bootstraps(calls), ['im.cocode.docker-disk-cleanup.plist'])

        out, _ = self.run_install(ROOT / 'macos', command='disk_cleanup_status')
        self.assertIn('✓ 3종 등록됨', out)

    def test_one_liner_downloads_and_failed_download_skips_safely(self):
        out, calls = self.run_install('', curl_ok=False)
        self.assertIn('내려받기 실패', out)
        self.assertEqual(self.bootstraps(calls), [])
        self.assertFalse((self.home / '.local/bin/cleanup-dart-tmp.sh').exists())

        out, _ = self.run_install('', command='disk_cleanup_status')
        self.assertIn('0/3', out)

        out, calls = self.run_install('', curl_ok=True)
        self.assertEqual(len(self.bootstraps(calls)), 3)
        self.assertTrue((self.home / '.local/bin/cleanup-dart-tmp.sh').exists())

    def test_option_and_docs_are_wired(self):
        source = SETUP.read_text()
        self.assertIn('--cleanup-only)', source)
        self.assertRegex(source, r'MODE_COUNT=\$\(\( ENV_ONLY \+ PERMS_ONLY \+ DART_ONLY \+ CLEANUP_ONLY \)\)')
        self.assertRegex(source, r'(?m)^install_disk_cleanup$')         # 전체 설치의 9.5단계 호출
        readme = (ROOT / 'macos/README.md').read_text()
        for job in JOBS:
            self.assertIn(f'im.cocode.{job}', readme)
        self.assertIn('--cleanup-only', readme)
        for platform in ('linux', 'windows'):
            self.assertIn('--cleanup-only', (ROOT / platform / 'README.md').read_text())


if __name__ == '__main__':
    unittest.main()
