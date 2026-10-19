#!/bin/sh
# self-hosted GitHub Actions 러너가 러너마다 따로 만든 캐시 사본을 회수한다.
# 러너가 없는 맥(대부분의 팀원 맥)에서는 대상이 없어 아무것도 하지 않는다.
#
# 러너는 서로의 캐시를 덮어쓰지 않도록 캐시를 러너마다 따로 둔다. 그 격리는 옳지만, 러너가 9개면
# 사본도 9개라 아무도 지우지 않으면 디스크가 찬다(2026-08-24 · 2026-10-19, 994GB 맥의 여유가
# 각각 6GB · 1.5GB 까지 떨어짐). 이 스크립트가 그 사본의 수명을 정한다.
#
# 대상 — 러너 이름 R 은 ~/actions/<R>/.runner 가 있는 폴더 이름이다:
#   러너별 캐시: 72시간(MIN_AGE_H) 동안 그 안에서 바뀐 파일이 없을 때
#     ~/.gradle-*  ~/.pub-cache-*                    러너별 Gradle · pub 캐시
#     ~/actions/_cache*/pub-*                        selfhost-prep 액션의 러너별 PUB_CACHE
#     ~/Library/Developer/Xcode/DerivedData-<R>      러너별 Xcode 빌드 캐시
#     ~/Library/Developer/Xcode/Archives-<R>.xcarchive
#     이름이 *-shared 인 것은 여러 러너가 함께 쓰므로 지우지 않는다.
#   러너 작업 폴더: 14일(CHECKOUT_MIN_AGE_H) 동안 그 안에서 바뀐 파일이 없을 때
#     ~/actions/<R>/_work/<저장소>                   _tool · _temp · _actions 처럼 _ 로 시작하는 것은 제외
#
# 지우는 조건 — 모두 만족해야 지운다:
#   ① 그 경로를 명령줄에 가진 프로세스가 없다
#   ② 그 안에서 작업 중인(cwd) 프로세스도, 그 안의 파일을 열고 있는 프로세스도 없다 (lsof)
#   ③ 위 기간 동안 그 안에서 바뀐 파일이 하나도 없다
#
# [왜 맨 위 폴더가 아니라 '안의 파일'을 보나]
#   예전 판은 맨 위 폴더의 수정 시각(stat -f %m)만 봤다. 그 값은 바로 아래 항목이 생기거나 지워질
#   때만 바뀌어서, 매일 쓰는 pub 캐시도 '75시간 전'으로 보였다(2026-10-19 실측: 맨 위 75시간,
#   안쪽은 72시간 안에 변경). 그래서 쓰고 있는 캐시를 지우고 다음 CI 가 다시 받는 왕복이 생겼다.
#
# [왜 작업 폴더만 14일인가]
#   unibook 의 prune-stale-flutter-sdk.yml 은 러너에 남아 있는 작업 폴더의 .fvmrc 를 모아 남길
#   Flutter SDK 를 정한다. 작업 폴더를 지우면 그 저장소의 SDK 도 다음 날 지워질 수 있어, 그 저장소의
#   다음 CI 가 클론과 SDK 다운로드(5~25분)를 둘 다 처음부터 한다. 며칠에 한 번 도는 저장소가 매번
#   그 값을 치르지 않도록, 이 맥에서 손을 뗀 저장소만 지운다.
#
# 이 스크립트가 하지 않는 것 — 다른 곳이 맡는다. 두 곳이 같은 대상을 지우면 서로의 보존 기준이
# 무의미해진다:
#   Flutter SDK 툴캐시(_work/_tool/flutter) → unibook 의 prune-stale-flutter-sdk.yml (보존 목록이 있다)
#   Docker(Colima)                         → cleanup-docker-disk.sh
#
# 미리 보기(지우지 않고 목록만): DRY_RUN=1 sh ~/.local/bin/cleanup-runner-cache.sh
# 설치: mac-setup.sh 가 ~/.local/bin 에 두고 launchd(im.cocode.runner-cache-cleanup, 24시간 주기)로 등록한다.
# 기록: ~/Library/Logs/runner-cache-cleanup.log
# 기준·대상 전체 설명: macos/disk-cleanup/README.md

MIN_AGE_H=${MIN_AGE_H:-72}
CHECKOUT_MIN_AGE_H=${CHECKOUT_MIN_AGE_H:-336}
DRY=${DRY_RUN:-0}
ACTIONS="$HOME/actions"
XCODE="$HOME/Library/Developer/Xcode"
LOG="$HOME/Library/Logs/runner-cache-cleanup.log"
SELF=${0##*/}
freed=0
ts() { date '+%Y-%m-%d %H:%M:%S'; }
gb() { awk -v k="$1" 'BEGIN{printf "%.2f GB", k/1048576}'; }

# 프로세스와 열린 파일(작업 폴더 포함)은 한 번만 찍어 둔다.
# 파일이 아니라 변수에 담는다 — 디스크가 꽉 찬 순간에도 동작해야 한다.
PROCS=$(ps -Ao command 2>/dev/null | grep -v -e grep -e "$SELF")
OPEN=$(lsof -n -Fn 2>/dev/null | sed -n 's/^n//p')

busy() {   # $1 = 경로 — 누가 쓰고 있으면 0
  printf '%s\n' "$PROCS" | grep -qF -- "$1" && return 0
  printf '%s\n' "$OPEN" | grep -qxF -- "$1" && return 0
  printf '%s\n' "$OPEN" | grep -qF -- "$1/" && return 0
  return 1
}

recent() {   # $1 = 경로, $2 = 시간 — 그 안에 그 시간 안에 바뀐 파일이 있으면 0 (첫 발견에서 멈춘다)
  [ -n "$(/usr/bin/find "$1" -mmin -$(( $2 * 60 )) -print -quit 2>/dev/null)" ]
}

reap() {   # $1 = 경로, $2 = 시간
  [ -e "$1" ] || return 0
  busy "$1" && return 0
  recent "$1" "$2" && return 0
  _kb=$(du -x -k -s "$1" 2>/dev/null | cut -f1)
  if [ "$DRY" = "1" ]; then
    echo "  [dry] ${1#"$HOME"/} $(gb "${_kb:-0}")"
    return 0
  fi
  rm -rf "$1" 2>/dev/null
  [ -e "$1" ] || freed=$((freed + ${_kb:-0}))
}

# 1) 러너별 캐시 사본
for p in "$HOME"/.gradle-* "$HOME"/.pub-cache-* "$ACTIONS"/_cache*/pub-*; do
  [ -d "$p" ] || continue
  case "${p##*/}" in *-shared) continue ;; esac
  reap "$p" "$MIN_AGE_H"
done

# 2) 러너 이름으로 찾는 Xcode 사본과 작업 폴더
for r in "$ACTIONS"/*/; do
  r=${r%/}
  [ -f "$r/.runner" ] || continue
  R=${r##*/}
  reap "$XCODE/DerivedData-$R" "$MIN_AGE_H"
  reap "$XCODE/Archives-$R.xcarchive" "$MIN_AGE_H"
  for p in "$r"/_work/*/; do
    p=${p%/}
    case "${p##*/}" in _*) continue ;; esac
    [ -d "$p" ] || continue
    reap "$p" "$CHECKOUT_MIN_AGE_H"
  done
done

if [ "$DRY" != "1" ] && [ "$freed" -gt 0 ]; then
  echo "$(ts) 회수 $(gb "$freed") · 여유 $(df -k / | awk 'NR==2{printf "%dGB", $4/1048576}')"
fi
# 기록이 끝없이 길어지지 않게 — 400줄을 넘으면 뒤쪽 200줄만 남긴다
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 400 ]; then
  tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG" || rm -f "$LOG.tmp"
fi
exit 0
