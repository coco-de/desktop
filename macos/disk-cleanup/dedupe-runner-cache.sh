#!/bin/sh
# self-hosted 러너가 러너마다 따로 받은 같은 파일(SDK · 패키지 캐시)을 APFS 복제로 한 벌 크기로 합친다.
# 러너가 둘 미만인 맥(대부분의 팀원 맥)에서는 합칠 사본이 없어 아무것도 하지 않는다.
#
# 러너는 서로의 캐시를 덮어쓰지 않도록 Flutter SDK · pub · Gradle 캐시를 러너마다 따로 둔다. 그 격리는
# 옳지만 러너가 8개면 같은 Flutter SDK 가 8벌, 같은 pub 패키지가 8벌 쌓인다(2026-11-13 실측: 사본 논리
# 크기 합 ~190GB 가 한 벌 크기로 줄었다). cleanup-runner-cache.sh 는 안 쓴 사본을 '지워서' 비우는데, 지운
# 사본은 다음 CI 가 다시 받아야 한다 — Flutter SDK 는 5~25분이고 느린 날은 시간 제한을 넘기기도 한다.
# 이 작업은 지우지 않는다. 내용이 같은 파일만 복제본(clonefile)으로 바꿔서, 각 러너가 완전한 사본을 그대로
# 가진 채 디스크 블록만 한 벌로 합친다. 러너가 늘어나거나 SDK 를 새로 받으면 사본이 다시 생기므로 하루마다
# 돌며, 이미 합쳐진 파일은 읽지 않고(물리 배치 비교) 건너뛰어 첫 회차 뒤에는 새로 생긴 파일만 읽는다.
#
# 바꾸는 조건 — 모두 만족해야 바꾼다:
#   ① 그 파일이 '쉬고 있는 러너'의 것이다 — 지금 잡(Runner.Worker)을 돌리는 러너의 파일은 읽기만 한다
#   ② 여러 러너가 함께 쓰는 공용 캐시(*-shared 등)가 아니다 — 원본으로 읽기만 하고 바꾸지 않는다
#   ③ 최근(DEDUPE_MIN_AGE, 기본 10분) 바뀐 파일이 아니고, 해시를 뜬 뒤 복제하는 사이에 바뀌지 않았다
#   ④ 쓰는 중에 바뀌는 이름이 아니다 — 락 · pid · 로그 · DB · _temp 는 빼고, Gradle 은 내려받은 산출물만,
#      pub 은 hosted · git 소스만 본다
# 심볼릭 링크 · 하드링크 · 빈 파일 · 압축 플래그가 붙은 파일 · 내용이 다른 파일은 건드리지 않고, 아무것도
# 지우지 않는다. 교체는 같은 폴더에 임시 이름으로 복제한 뒤 이름만 바꾸므로 읽는 쪽은 옛 파일이나 새
# 파일 중 하나를 온전히 본다.
#
# 대상 사본 폴더 (러너 이름 R 은 ~/actions/<R>/.runner 가 있는 폴더 이름이다):
#   ~/actions/<R>/_work/_tool/flutter/*  ·  _tool/flutter-<R>/*     러너별 Flutter SDK (버전 사이의 겹침도 합친다)
#   ~/.pub-cache-*  ·  ~/actions/_cache*/pub*  ·  _tool/pub-cache-*  ·  <임시 폴더>/*pub-cache*   pub 캐시
#   ~/.gradle-*  ·  ~/actions/_cache*/gradle                         Gradle 홈
#   ~/actions/<R>/_work/_tool/<그 밖의 도구>                         dart · node · JDK · uv 등
#
# 시간 제한: 한 번에 DEDUPE_MAX_SECONDS(기본 7200초)까지만 일한다. 처음 돌리는 러너 맥은 사본이 수백 GB 라
# 몇 번에 나눠 끝나고, 이후는 새로 생긴 것만 처리해 몇 분이면 끝난다.
#
# 미리 보기(바꾸지 않고 수만 보기): DRY_RUN=1 sh ~/.local/bin/dedupe-runner-cache.sh
# 설치: mac-setup.sh 가 ~/.local/bin 에 두고 launchd(im.cocode.runner-cache-dedupe, 24시간 주기)로 등록한다.
#       실제 일은 옆의 dedupe-runner-cache.py 가 한다(python3 필요 — 개발자 도구와 함께 깔린다).
# 기록: ~/Library/Logs/runner-cache-dedupe.log (무언가 바꿨거나 문제가 있을 때만 한 줄)
# 기준·대상 전체 설명: macos/disk-cleanup/README.md

DRY=${DRY_RUN:-0}
ACTIONS="$HOME/actions"
LOG="$HOME/Library/Logs/runner-cache-dedupe.log"
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
ENGINE=${DEDUPE_ENGINE:-$HERE/dedupe-runner-cache.py}
ts() { date '+%Y-%m-%d %H:%M:%S'; }
gb() { awk -v b="${1:-0}" 'BEGIN{printf "%.2f GB", b/1073741824}'; }

# APFS 복제는 macOS 에만 있다
[ "$(uname -s)" = Darwin ] || exit 0

# 합칠 사본이 있으려면 러너가 둘 이상이어야 한다
runners=0
for r in "$ACTIONS"/*/; do
  [ -f "${r}.runner" ] && runners=$((runners + 1))
done
[ "$runners" -ge 2 ] || exit 0

# python3 — 개발자 도구가 없으면 /usr/bin/python3 는 실행 대신 설치 안내 창을 띄우므로 먼저 확인한다
if [ -n "${DEDUPE_PYTHON:-}" ]; then
  PY=$DEDUPE_PYTHON
else
  PY=/usr/bin/python3
  [ -x "$PY" ] && xcode-select -p >/dev/null 2>&1 || exit 0
fi
[ -f "$ENGINE" ] || exit 0

# 이전 회차가 아직 돌고 있으면 겹쳐 돌지 않는다 (잠금 폴더는 못 만들어도 — 디스크가 가득 찬 때 — 그냥 진행한다)
LOCK="$HOME/Library/Caches/im.cocode.runner-cache-dedupe.lock"
mkdir -p "$HOME/Library/Caches" 2>/dev/null
if mkdir "$LOCK" 2>/dev/null; then
  :
elif [ -d "$LOCK" ]; then
  old=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null
fi
if [ -d "$LOCK" ]; then
  echo $$ > "$LOCK/pid" 2>/dev/null
  trap 'rm -rf "$LOCK"' EXIT INT TERM HUP
fi

set -- "$PY" -I "$ENGINE" --home "$HOME" \
  --workers "${DEDUPE_WORKERS:-2}" \
  --max-seconds "${DEDUPE_MAX_SECONDS:-7200}" \
  --min-age "${DEDUPE_MIN_AGE:-600}"
[ -n "${DEDUPE_TMP_DIR:-}" ] && set -- "$@" --tmp-dir "$DEDUPE_TMP_DIR"
[ "$DRY" = "1" ] || set -- "$@" --apply

OUT=$("$@" 2>&1)
RES=$(printf '%s\n' "$OUT" | sed -n 's/^RESULT //p' | tail -1)
field() { printf '%s\n' "$RES" | tr ' ' '\n' | sed -n "s/^$1=//p" | tail -1; }
num() { v=$(field "$1"); echo "${v:-0}"; }

if [ -z "$RES" ]; then
  # 엔진이 결과를 못 남기고 끝났다 — 이유를 기록에 남기고 다음 회차를 기다린다
  printf '%s ⚠ 중복 제거 실패 — %s\n' "$(ts)" "$(printf '%s' "$OUT" | tail -1 | cut -c1-200)"
  exit 0
fi

if [ "$DRY" = "1" ]; then
  printf '%s\n' "$OUT" | sed -n 's/^ERR /  ⚠ /p'
  echo "  [dry] 바꿀 파일 $(num would_replace)개 (논리 $(gb "$(num would_bytes)")) · 이미 한 벌로 합쳐진 파일 $(num already_shared)개 · 실행 중인 러너 때문에 건너뜀 $(num skipped_busy)개"
  exit 0
fi

replaced=$(num replaced)
errors=$(num errors)
limited=$(num limited)
if [ "$replaced" -gt 0 ] || [ "$errors" -gt 0 ] || [ "$limited" -gt 0 ]; then
  line="$(ts) 중복 제거 파일 ${replaced}개 (논리 $(gb "$(num replaced_bytes)"))"
  line="$line · 건너뜀(실행 중인 러너 $(num skipped_busy) · 최근 바뀜 $(num skipped_recent) · 그 사이 바뀜 $(num skipped_changed))"
  [ "$errors" -gt 0 ] && line="$line · ⚠ 오류 ${errors}건"
  [ "$limited" -gt 0 ] && line="$line · 시간 제한에서 멈춤(다음 회차에 이어서)"
  line="$line · 여유 $(df -k "$HOME" | awk 'NR==2{printf "%dGB", $4/1048576}')"
  printf '%s\n' "$line"
  printf '%s\n' "$OUT" | sed -n 's/^ERR /  ⚠ /p' | head -5
fi
# 기록이 끝없이 길어지지 않게 — 400줄을 넘으면 뒤쪽 200줄만 남긴다
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 400 ]; then
  tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG" || rm -f "$LOG.tmp"
fi
exit 0
