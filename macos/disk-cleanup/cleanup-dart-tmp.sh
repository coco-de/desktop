#!/bin/sh
# Flutter·Dart 테스트가 비정상 종료하며 임시 폴더($TMPDIR)에 남기는 폴더를 정리한다.
#   - dart_test.kernel.*  : `dart test` 가 테스트 파일마다 컴파일한 결과물. 개당 수 GB~수십 GB
#   - flutter_tools.*     : flutter 명령의 임시 작업 폴더
# 테스트를 중간에 끊거나(Ctrl+C) CI 잡이 취소되면 이 폴더가 그대로 남는다. 러너가 상시 도는 맥에서는
# 하루 30GB 넘게 쌓인 적이 있다(2026-08-24 · 2026-09-28, 디스크 여유가 한 자릿수 GB 까지 떨어짐).
#
# 지우는 조건 — 둘 다 만족해야 지운다:
#   ① 실행 중인 프로세스가 그 폴더를 가리키지 않는다 (ps 의 명령줄 · lsof 의 열린 파일)
#   ② 일정 시간 동안 그 안에서 바뀐 파일이 하나도 없다
#        dart_test.kernel.* : 70분 (MIN_AGE_KERNEL_M) — CI 잡 상한 60분 + 여유
#        flutter_tools.*    : 6시간 (MIN_AGE_H)
#   ①은 조회 순간의 스냅샷이라 그 사이에 시작된 실행을 놓칠 수 있고, ②가 그 틈을 막는다.
#   dart_test.kernel.* 는 추가로, 그 폴더의 test.dart 가 가리키는 러너·워크트리에서
#   `dart test` 가 아직 돌고 있으면 건너뛴다.
#
# [예전 판의 결함 두 가지 — 같은 실수를 하지 않도록 남겨 둔다]
#   - ②가 제대로 동작하지 않았다. 기준 시각을 `2026-10-19T08:04:57` 처럼 날짜와 시각 사이에 T 를
#     넣어 `find -newermt` 에 넘겼는데, macOS find 는 이 형식을 다른 시각으로 읽는다. 실측
#     (2026-10-19): 70분 기준은 5분 전에 바뀐 폴더도 '오래됨'으로 판정해 사실상 꺼져 있었고,
#     6시간 기준은 약 4시간으로 줄어 있었다. 실행 중인 테스트는 ①의 스냅샷 하나로만 보호되고
#     있었다. 그래서 날짜 문자열을 만들지 않고 `find -mmin` 으로 분 단위를 직접 센다.
#   - 디스크가 꽉 찬 순간에 정리가 멈췄다. 사용 중 목록을 임시 파일(mktemp)에 적었는데, 디스크가
#     가득 차면 그 파일을 만들지 못해 그 회차를 통째로 건너뛰었다(기록: "mkstemp failed ... No space
#     left on device"). 정리가 가장 필요한 순간이다. 그래서 목록을 파일이 아니라 변수에 담는다.
#
# 설치: mac-setup.sh 가 ~/.local/bin 에 두고 launchd(im.cocode.dart-tmp-cleanup, 15분 주기)로 등록한다.
#       정리 작업만 다시 등록하려면: ./mac-setup.sh --cleanup-only
# 기록: ~/Library/Logs/dart-tmp-cleanup.log
# 기준·대상 전체 설명: macos/disk-cleanup/README.md

# CLEANUP_TMP_DIR 은 회귀 테스트가 임시 폴더를 바꿔 끼우는 자리다. 평소에는 비어 있다.
T=${CLEANUP_TMP_DIR:-$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)}
[ -n "$T" ] && [ -d "$T" ] || exit 0
MIN_AGE_H=${MIN_AGE_H:-6}
MIN_AGE_KERNEL_M=${MIN_AGE_KERNEL_M:-70}
LOG="$HOME/Library/Logs/dart-tmp-cleanup.log"
freed=0
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# 사용 중인 폴더 이름 목록 — 파일이 아니라 변수에 담는다(디스크가 꽉 차도 동작해야 한다)
INUSE=$( { ps -Ao command 2>/dev/null; lsof -n 2>/dev/null; } \
  | grep -oE '(dart_test\.kernel|flutter_tools)\.[A-Za-z0-9_]+' | sort -u )

for d in "$T"/dart_test.kernel.* "$T"/flutter_tools.*; do
  [ -d "$d" ] || continue
  b=${d##*/}
  printf '%s\n' "$INUSE" | grep -qxF -- "$b" && continue
  case "$b" in
    dart_test.kernel.*)
      # 그 커널을 만든 러너·워크트리에서 dart test 가 아직 돌면 건너뛴다
      owner=$(grep -oE '(actions/[A-Za-z0-9_-]+|workspaces/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+)' "$d/test.dart" 2>/dev/null | head -1)
      if [ -n "$owner" ] && ps -Ao command 2>/dev/null | grep -v grep | grep -F -- "$owner" | grep -q 'test'; then
        continue
      fi
      age_m=$MIN_AGE_KERNEL_M
      ;;
    *)
      age_m=$((MIN_AGE_H * 60))
      ;;
  esac
  # age_m 분 안에 바뀐 파일이 하나라도 있으면 아직 쓰는 중 — 첫 발견에서 멈춘다(-quit, 큰 폴더 대비)
  [ -n "$(/usr/bin/find "$d" -mmin -"$age_m" -print -quit 2>/dev/null)" ] && continue
  kb=$(du -x -k -s "$d" 2>/dev/null | cut -f1)
  rm -rf "$d" 2>/dev/null
  [ -e "$d" ] || freed=$((freed + ${kb:-0}))
done

if [ "$freed" -gt 0 ]; then
  echo "$(ts) 회수 $(awk -v k="$freed" 'BEGIN{printf "%.2f GB", k/1048576}') · 여유 $(df -k / | awk 'NR==2{printf "%dGB", $4/1048576}')"
fi
# 기록이 끝없이 길어지지 않게 — 400줄을 넘으면 뒤쪽 200줄만 남긴다
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 400 ]; then
  tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG" || rm -f "$LOG.tmp"
fi
exit 0
