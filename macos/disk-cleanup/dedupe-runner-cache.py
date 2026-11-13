#!/usr/bin/env python3
"""러너 캐시 사본 중복 제거 — 내용이 같은 파일을 APFS 복제(clonefile)로 한 벌 크기로 합친다.

[왜 필요한가]
self-hosted 러너는 서로의 캐시를 덮어쓰지 않도록 SDK·패키지 캐시를 러너마다 따로 둡니다. 그 격리는
옳지만, 러너가 8개면 같은 Flutter SDK 가 8벌, 같은 pub 패키지가 8벌 쌓입니다(2026-11-13 실측: 사본
논리 크기 ~190GB 가 한 벌 크기로 줄었습니다). 사본을 지우면 다음 CI 가 SDK 를 다시 받느라 5~25분을
쓰고, 느린 날은 시간 제한을 넘기기도 합니다. 그래서 지우지 않고 **내용이 같은 파일만 복제본으로 바꿔**
각 러너가 완전한 사본을 그대로 가진 채 디스크 블록만 한 벌로 합칩니다.

[무엇을 하나]
  1. 같은 종류의 사본 폴더(예: 러너별 Flutter SDK 폴더들)를 **같은 상대 경로로 동시에** 걷습니다.
  2. 둘 이상에 있는 일반 파일 중 크기가 같은 것의 **물리 배치**(F_LOG2PHYS_EXT)를 봅니다. 이미 복제로
     합쳐진 파일은 배치가 같아 읽지 않고 건너뜁니다 — 그래서 첫 회차 뒤에는 새로 생긴 파일만 읽습니다.
  3. 배치가 다른 것만 SHA-256 으로 비교하고, 같으면 한 파일을 원본으로 삼아 나머지를
     clonefile(원본) → 같은 폴더의 임시 이름 → 원래 파일의 모드·mtime 복원 → rename 으로 바꿉니다.

[안전 기준]
  · 바꾸는 파일은 **쉬고 있는 러너의 것**뿐입니다. 지금 잡을 돌리는 러너(Runner.Worker 가 있는 러너)와
    여러 러너가 함께 쓰는 공용 캐시(`*-shared` 등)는 원본으로만 읽고 절대 바꾸지 않습니다.
  · 바꾸기 직전마다 그 러너가 아직 쉬는지 다시 보고, 최근(기본 10분) 바뀐 파일과 해시·복제 사이에
    바뀐 파일(inode·크기·mtime)은 건너뜁니다.
  · 쓰는 중에 바뀌는 파일은 대상이 아닙니다 — 락·pid·로그·DB·`_temp` 같은 이름은 빼고, Gradle 은 내려받은
    산출물(`files-2.1` · `wrapper/dists` …)만, pub 은 `hosted` · `git` 소스만 봅니다.
  · 심볼릭 링크 · 하드링크(nlink>1) · 빈 파일 · 플래그가 붙은 파일(압축 등) · 한 사본에만 있는 파일 ·
    내용이 다른 파일은 건드리지 않습니다. 아무것도 지우지 않습니다.
  · 교체는 임시 이름으로 만든 뒤 rename 하므로 읽는 쪽은 옛 파일이나 새 파일 중 하나를 온전히 봅니다.

[사용]
  dedupe-runner-cache.py [--apply] [--home DIR] [--tmp-dir DIR] [--workers N]
                         [--max-seconds S] [--min-age S]
  --apply 가 없으면 아무것도 바꾸지 않고, 바꿀 파일 수와 논리 크기만 센다(미리 보기).
  마지막 줄은 `RESULT key=value ...` 형식이라 감싸는 셸 스크립트가 읽습니다.
  보통은 dedupe-runner-cache.sh 로 부릅니다 — 러너가 둘 이상 있는 맥에서만 일합니다.
"""
import argparse
import ctypes
import errno
import fcntl
import fnmatch
import glob
import hashlib
import itertools
import os
import re
import stat
import struct
import subprocess
import sys
import threading
import time
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor

F_LOG2PHYS_EXT = 65                  # <sys/fcntl.h> — Python 3.9 의 fcntl 모듈에는 상수가 없다
L2P = struct.Struct('=Iqq')          # struct log2phys (#pragma pack(4), 20바이트): flags · contigbytes · devoffset
CLONE_NOFOLLOW = 0x0001

# 쓰는 중에 바뀌거나 잠금에 쓰이는 이름 — 같은 내용이어도 바꾸지 않는다
DENY_DIRS = frozenset(['_temp', '.tmp', 'tmp', 'locks', 'daemon', '.cache'])
DENY_FILES = ('lockfile', '*.lock', '*.lck', '*.pid', '*.sock', '*.log', '*.tmp', '.DS_Store',
              '*.db', '*.db-*', '*.sqlite*', '*.wal', '*.shm')
OWN_TEMP = re.compile(r'^\.dd\d+_\d+_\d+$')          # 이 도구가 만드는 임시 이름

Root = namedtuple('Root', 'path owner')               # owner: 러너 이름, 공용·알 수 없는 사본은 None(읽기 전용)
Info = namedtuple('Info', 'root path st')


class Family(object):
    """같은 상대 경로 구조를 가진 사본 폴더들의 묶음."""

    def __init__(self, name, roots, allow=None, deny_rel=None, deny_file=None):
        self.name = name
        self.roots = roots
        self.allow = [p.split('/') for p in allow] if allow else None   # 상대 경로 접두사(세그먼트별 fnmatch)
        self.deny_rel = re.compile(deny_rel) if deny_rel else None
        self.deny_file = re.compile(deny_file) if deny_file else None

    def dir_ok(self, segs):
        """이 폴더 안에 허용 경로가 있을 수 있거나 이미 허용 경로 안이면 True."""
        if self.deny_rel and self.deny_rel.search('/'.join(segs)):
            return False
        if self.allow is None:
            return True
        for pat in self.allow:
            n = min(len(pat), len(segs))
            if all(fnmatch.fnmatchcase(segs[i], pat[i]) for i in range(n)):
                return True
        return False

    def file_ok(self, segs):
        if self.deny_rel and self.deny_rel.search('/'.join(segs)):
            return False
        if self.deny_file and self.deny_file.search(segs[-1]):
            return False
        if self.allow is None:
            return True
        for pat in self.allow:
            if len(segs) > len(pat) and all(fnmatch.fnmatchcase(segs[i], pat[i]) for i in range(len(pat))):
                return True
        return False


def physical_signature(path, size):
    """파일의 물리 배치((장치 오프셋, 연속 길이) 목록). 복제본끼리는 같고 실제 복사본은 다르다. 모르면 None."""
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return None
    try:
        runs, off = [], 0
        while off < size:
            out = fcntl.fcntl(fd, F_LOG2PHYS_EXT, L2P.pack(0, size - off, off))
            _flags, contig, dev = L2P.unpack(out)
            if contig <= 0 or len(runs) > 4096:
                return None
            runs.append((dev, contig))
            off += contig
        return tuple(runs)
    except (OSError, struct.error):
        return None
    finally:
        os.close(fd)


def is_candidate(st):
    return (stat.S_ISREG(st.st_mode) and st.st_size > 0 and st.st_nlink == 1
            and not getattr(st, 'st_flags', 0))


class Busy(object):
    """지금 잡(Runner.Worker)을 돌리는 러너 — ps 스냅샷을 잠깐(ttl초) 재사용한다."""

    def __init__(self, actions_dir, runners, ttl):
        self.actions = actions_dir.rstrip('/') + '/'
        self.runners = runners
        self.ttl = ttl
        self.t = None
        self.busy = set()
        self.lock = threading.Lock()

    def refresh(self):
        try:
            out = subprocess.run(['ps', '-Ao', 'command'], capture_output=True, text=True, timeout=30).stdout
        except (OSError, subprocess.SubprocessError):
            # 못 읽으면 전부 바쁜 것으로 본다 — 모르는 채로 바꾸지 않는다
            self.busy = set(self.runners)
            self.t = time.monotonic()
            return
        busy = set()
        for line in out.splitlines():
            if 'Runner.Worker' not in line:
                continue
            for r in self.runners:
                if (self.actions + r + '/') in line:
                    busy.add(r)
        self.busy = busy
        self.t = time.monotonic()

    def is_busy(self, runner):
        with self.lock:
            if self.t is None or time.monotonic() - self.t > self.ttl:
                self.refresh()
            return runner in self.busy


class Engine(object):
    def __init__(self, args, libc, busy):
        self.args = args
        self.libc = libc
        self.busy = busy
        self.lock = threading.Lock()
        self.counter = itertools.count()
        self.stats = dict(files_seen=0, already_shared=0, dup_files=0, dup_bytes=0, replaced=0,
                          replaced_bytes=0, would_replace=0, would_bytes=0, skipped_busy=0,
                          skipped_recent=0, skipped_changed=0, skipped_other=0, errors=0,
                          hashed_bytes=0, limited=0)
        self.err_samples = []
        self.deadline = time.monotonic() + args.max_seconds if args.max_seconds > 0 else None
        self.stop = False

    # ---- 보조 ----
    def bump(self, **kw):
        with self.lock:
            for k, v in kw.items():
                self.stats[k] += v

    def note_err(self, msg):
        with self.lock:
            self.stats['errors'] += 1
            if len(self.err_samples) < 20:
                self.err_samples.append(msg)

    def out_of_time(self):
        if self.stop:
            return True
        if self.deadline is not None and time.monotonic() > self.deadline:
            self.stop = True
            self.bump(limited=1)
        return self.stop

    def sha256(self, path):
        h = hashlib.sha256()
        n = 0
        with open(path, 'rb', buffering=0) as f:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                h.update(b)
                n += len(b)
        self.bump(hashed_bytes=n)
        return h.hexdigest()

    def fixed(self, info):
        """바꾸지 않는 파일 — 공용 사본이거나 지금 잡을 돌리는 러너의 것."""
        return info.root.owner is None or self.busy.is_busy(info.root.owner)

    # ---- 교체 ----
    def replace(self, canon, tgt):
        """tgt 를 canon 의 복제본으로 원자적으로 바꾼다. 바꿨으면 True."""
        d = os.path.dirname(tgt.path)
        tmp = os.path.join(d, '.dd%d_%d_%d' % (os.getpid(), threading.get_ident() % 100000, next(self.counter)))
        try:
            cur = os.lstat(canon.path)
            if (cur.st_ino, cur.st_size, cur.st_mtime_ns) != (canon.st.st_ino, canon.st.st_size, canon.st.st_mtime_ns):
                self.bump(skipped_changed=1)
                return False
            if self.libc.clonefile(os.fsencode(canon.path), os.fsencode(tmp), CLONE_NOFOLLOW) != 0:
                err = ctypes.get_errno()
                self.note_err('clonefile errno=%d %s' % (err, tgt.path))
                if err in (errno.ENOTSUP, errno.EXDEV):
                    self.stop = True                  # 복제를 못 하는 볼륨 — 같은 오류를 쌓지 않고 멈춘다
                return False
            try:
                cur = os.lstat(tgt.path)
                if (cur.st_ino, cur.st_size, cur.st_mtime_ns) != (tgt.st.st_ino, tgt.st.st_size, tgt.st.st_mtime_ns):
                    self.bump(skipped_changed=1)
                    os.unlink(tmp)
                    return False
                if self.busy.is_busy(tgt.root.owner):          # 바꾸기 직전에 한 번 더 — 그 사이 잡이 시작됐을 수 있다
                    self.bump(skipped_busy=1)
                    os.unlink(tmp)
                    return False
                if os.lstat(tmp).st_size != tgt.st.st_size:
                    self.note_err('복제 크기 불일치 %s' % tgt.path)
                    os.unlink(tmp)
                    return False
                os.chmod(tmp, stat.S_IMODE(tgt.st.st_mode))
                os.utime(tmp, ns=(tgt.st.st_atime_ns, tgt.st.st_mtime_ns))
                os.rename(tmp, tgt.path)
            except BaseException:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                raise
            return True
        except OSError as e:
            self.note_err('%s %s' % (e, tgt.path))
            return False

    # ---- 같은 상대 경로의 파일 묶음 처리 ----
    def process(self, entries):
        infos = []
        for root, e in entries:
            try:
                st = e.stat(follow_symlinks=False)
            except OSError:
                continue
            self.bump(files_seen=1)
            if not is_candidate(st):
                self.bump(skipped_other=1)
                continue
            infos.append(Info(root, e.path, st))
        if len(infos) < 2:
            return
        by_size = {}
        for i in infos:
            by_size.setdefault((i.st.st_size, i.st.st_dev), []).append(i)
        for lst in by_size.values():
            if len(lst) >= 2:
                self.process_same_size(lst)

    def process_same_size(self, lst):
        groups = {}
        for i in lst:
            sig = physical_signature(i.path, i.st.st_size)
            groups.setdefault(sig if sig is not None else ('unique', i.path), []).append(i)
        if len(groups) < 2:
            self.bump(already_shared=len(lst))          # 전부 같은 물리 블록 — 읽을 것이 없다
            return
        by_digest = {}
        for members in groups.values():
            try:
                digest = self.sha256(members[0].path)   # 같은 배치의 파일은 내용도 같으니 하나만 읽는다
            except OSError as e:
                self.note_err('해시 %s %s' % (e, members[0].path))
                continue
            by_digest.setdefault(digest, []).append(members)
        for sgroups in by_digest.values():
            if len(sgroups) >= 2:
                self.merge(sgroups)

    def merge(self, sgroups):
        # 원본 묶음: 바꾸지 않는 파일이 든 묶음 우선 → 파일이 많은 묶음 → 경로 사전순
        def rank(g):
            return (0 if any(self.fixed(i) for i in g) else 1, -len(g), min(i.path for i in g))
        canon_group = min(sgroups, key=rank)
        fixed_in = [i for i in canon_group if self.fixed(i)]
        canon = (fixed_in or sorted(canon_group, key=lambda i: i.path))[0]
        for g in sgroups:
            if g is canon_group:
                continue
            for tgt in g:
                size = tgt.st.st_size
                self.bump(dup_files=1, dup_bytes=size)
                if tgt.root.owner is None:
                    self.bump(skipped_other=1)                      # 공용 사본은 바꾸지 않는다
                    continue
                if self.busy.is_busy(tgt.root.owner):
                    self.bump(skipped_busy=1)
                    continue
                if time.time() - tgt.st.st_mtime < self.args.min_age:
                    self.bump(skipped_recent=1)
                    continue
                if not self.args.apply:
                    self.bump(would_replace=1, would_bytes=size)
                    continue
                if self.replace(canon, tgt):
                    self.bump(replaced=1, replaced_bytes=size)

    # ---- 사본 폴더 동시 순회 ----
    def walk(self, fam, members, segs, pool, sem, futs):
        """members: [(Root, 폴더 경로)] — 같은 상대 경로(segs)의 폴더들."""
        names = {}
        for root, d in members:
            try:
                with os.scandir(d) as it:
                    for e in it:
                        names.setdefault(e.name, []).append((root, e))
            except OSError:
                continue
        for name, ents in names.items():
            if len(ents) < 2 or OWN_TEMP.match(name):
                continue
            if self.out_of_time():
                return
            sub, files = [], []
            for root, e in ents:
                try:
                    if e.is_symlink():
                        continue
                    if e.is_dir(follow_symlinks=False):
                        sub.append((root, e.path))
                    elif e.is_file(follow_symlinks=False):
                        files.append((root, e))
                except OSError:
                    continue
            child = segs + [name]
            if len(sub) >= 2 and name not in DENY_DIRS and fam.dir_ok(child):
                self.walk(fam, sub, child, pool, sem, futs)
            if len(files) >= 2 and fam.file_ok(child) and not any(fnmatch.fnmatchcase(name, p) for p in DENY_FILES):
                sem.acquire()
                f = pool.submit(self.process, files)
                f.add_done_callback(lambda _f: sem.release())
                futs.append(f)
                if len(futs) > 5000:
                    futs[:] = [x for x in futs if not x.done()]

    def run_family(self, fam):
        roots = [r for r in fam.roots if os.path.isdir(r.path)]
        if len(roots) < 2:
            return
        pool = ThreadPoolExecutor(max_workers=self.args.workers)
        sem = threading.Semaphore(self.args.workers * 64)
        futs = []
        try:
            self.walk(fam, [(r, r.path) for r in roots], [], pool, sem, futs)
        finally:
            pool.shutdown(wait=True)
        for f in futs:
            try:
                f.result()
            except Exception as e:                           # 한 묶음의 예외가 회차 전체를 막지 않게
                self.note_err('내부 오류 %r' % (e,))


# ---- 사본 폴더 찾기 ----
def discover(home, tmp_dir):
    """(러너 이름들, Family 목록). 러너 = ~/actions/<이름>/.runner 가 있는 폴더."""
    actions = os.path.join(home, 'actions')
    try:
        names = sorted(os.listdir(actions))
    except OSError:
        return [], []
    runners = [n for n in names if os.path.isfile(os.path.join(actions, n, '.runner'))]

    def owner_of(name):
        # 이름 끝이 '-<러너>' 인 러너. 러너 이름이 다른 러너 이름의 끝과 겹쳐도 가장 긴 쪽을 고른다
        hits = [r for r in runners if name == r or name.endswith('-' + r)]
        return max(hits, key=len) if hits else None

    def dirs(pattern):
        return sorted(p for p in glob.glob(pattern) if os.path.isdir(p) and not os.path.islink(p))

    families = []

    flutter = []
    for r in runners:
        tool = os.path.join(actions, r, '_work', '_tool')
        for sub in dirs(os.path.join(tool, 'flutter', '*')) + dirs(os.path.join(tool, 'flutter-*', '*')):
            flutter.append(Root(sub, r))
    families.append(Family('flutter', flutter))

    pub = []
    for p in dirs(os.path.join(actions, '_cache*', 'pub*')) + dirs(os.path.join(home, '.pub-cache-*')) \
            + dirs(os.path.join(tmp_dir, '*pub-cache*')):
        pub.append(Root(p, owner_of(os.path.basename(p))))
    for r in runners:
        for p in dirs(os.path.join(actions, r, '_work', '_tool', 'pub-cache-*')):
            pub.append(Root(p, r))
    families.append(Family('pub', pub, allow=['hosted', 'hosted-hashes', 'git'], deny_rel=r'^git/cache(/|$)'))

    gradle = [Root(p, owner_of(os.path.basename(p))) for p in dirs(os.path.join(home, '.gradle-*'))]
    gradle += [Root(p, None) for p in dirs(os.path.join(actions, '_cache*', 'gradle'))]
    families.append(Family('gradle', gradle,
                           allow=['caches/modules-2/files-2.1', 'wrapper/dists', 'caches/*/generated-gradle-jars',
                                  'caches/jars-*', 'caches/transforms-*'],
                           deny_file=r'\.(bin|properties)$'))

    tools = set()
    for r in runners:
        tool = os.path.join(actions, r, '_work', '_tool')
        try:
            for n in os.listdir(tool):
                if n != 'flutter' and not n.startswith(('flutter-', 'pub-cache-')):
                    tools.add(n)
        except OSError:
            pass
    for n in sorted(tools):
        roots = [Root(os.path.join(actions, r, '_work', '_tool', n), r) for r in runners
                 if os.path.isdir(os.path.join(actions, r, '_work', '_tool', n))]
        families.append(Family('tool/' + n, roots))
    return runners, families


def main(argv=None):
    ap = argparse.ArgumentParser(description='러너 캐시 사본을 APFS 복제로 한 벌 크기로 합친다')
    ap.add_argument('--apply', action='store_true', help='실제로 바꾼다 (없으면 미리 보기)')
    ap.add_argument('--home', default=os.path.expanduser('~'))
    ap.add_argument('--tmp-dir', default='/private/tmp', help='러너별 pub 캐시가 생기는 임시 폴더')
    ap.add_argument('--workers', type=int, default=2)
    ap.add_argument('--max-seconds', type=int, default=7200, help='이 시간이 지나면 새 묶음을 시작하지 않는다 (0 = 제한 없음)')
    ap.add_argument('--min-age', type=int, default=600, help='이 초 안에 바뀐 파일은 바꾸지 않는다')
    ap.add_argument('--busy-ttl', type=float, default=5.0)
    args = ap.parse_args(argv)

    if sys.platform != 'darwin':
        print('RESULT skipped=not-macos')
        return 0
    libc = ctypes.CDLL('libc.dylib', use_errno=True)
    libc.clonefile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    libc.clonefile.restype = ctypes.c_int

    runners, families = discover(args.home, args.tmp_dir)
    if len(runners) < 2:
        print('RESULT skipped=runners<2 runners=%d' % len(runners))
        return 0
    busy = Busy(os.path.join(args.home, 'actions'), runners, args.busy_ttl)
    engine = Engine(args, libc, busy)
    for fam in families:
        if engine.out_of_time():
            break
        engine.run_family(fam)
    s = engine.stats
    for m in engine.err_samples:
        print('ERR', m)
    print('RESULT runners=%d mode=%s ' % (len(runners), 'apply' if args.apply else 'dry')
          + ' '.join('%s=%d' % (k, v) for k, v in s.items()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
