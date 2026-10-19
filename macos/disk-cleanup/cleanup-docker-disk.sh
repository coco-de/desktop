#!/bin/sh
# Colima(맥에서 Docker 를 돌리는 리눅스 VM)의 디스크를 회수한다.
# Colima 가 꺼져 있으면 아무것도 하지 않는다 — 켜지도 끄지도 않는다.
#
# 하는 일 — 모두 '지금 아무도 쓰지 않는 것'만:
#   1) 빌드 캐시: 72시간(MIN_AGE_H) 동안 쓰지 않은 것 (docker builder prune --filter until=72h)
#   2) 주인 없는 익명 볼륨: 어떤 컨테이너(멈춘 것 포함)에도 붙어 있지 않고, 이름이 자동으로 붙은
#      64자리 해시이며, 만든 지 72시간이 넘은 것. CI 의 테스트 DB 컨테이너가 지워지며 남긴 볼륨이
#      이 모양이다(2026-10-19 실측 106개 · 개당 약 115MB). 익명 볼륨은 다음 실행이 다시 붙여 쓰지
#      못하므로 남겨 둘 이유가 없다. 이름 붙은 볼륨은 일부러 남긴 데이터일 수 있어 지우지 않는다.
#   3) fstrim: VM 안에서 지운 공간을 맥 디스크로 돌려준다. Colima 데이터 디스크는 한 번 커지면 VM
#      안에서 지워도 맥 쪽 파일이 줄지 않는다 — 이 단계가 없으면 위에서 지운 만큼 맥 여유가 늘지 않는다.
#
# 하지 않는 것:
#   이미지 삭제 — 직접 빌드해 다시 만드는 데 오래 걸리는 이미지가 섞여 있다
#   컨테이너·네트워크 삭제, colima stop/delete — 실행 중인 작업(다른 러너의 CI 포함)을 끊는다
#   docker system prune --volumes · docker volume prune — 위 2) 의 이름·나이 조건 없이 지운다
#
# 러너 호스트에서는 unibook 의 reclaim-docker-disk.yml 이 매일 이미지·빌드 캐시 정리와 fstrim 을 한다.
# 이 스크립트가 그와 겹쳐 돌아도 무해하다(이미 지운 것은 다시 지울 게 없다). 그 워크플로가 손대지 않는
# 2) 를 더 맡는다.
#
# 미리 보기(지우지 않고 목록만): DRY_RUN=1 sh ~/.local/bin/cleanup-docker-disk.sh
# 설치: mac-setup.sh 가 ~/.local/bin 에 두고 launchd(im.cocode.docker-disk-cleanup, 24시간 주기)로 등록한다.
# 기록: ~/Library/Logs/docker-disk-cleanup.log
# 기준·대상 전체 설명: macos/disk-cleanup/README.md

MIN_AGE_H=${MIN_AGE_H:-72}
DRY=${DRY_RUN:-0}
CMD_TIMEOUT=${DOCKER_CMD_TIMEOUT:-600}
LOG="$HOME/Library/Logs/docker-disk-cleanup.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# launchd 는 로그인 셸이 아니라 PATH 가 짧다 — docker 를 못 찾을 때만 Homebrew 경로를 붙인다
command -v docker >/dev/null 2>&1 || { PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH; }
command -v docker >/dev/null 2>&1 || exit 0
command -v colima >/dev/null 2>&1 || exit 0

# macOS 에는 timeout 명령이 없다 — 멈춘 데몬이 이 작업을 붙잡고 있지 않도록 perl 알람으로 자른다
limit() { perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$CMD_TIMEOUT" "$@"; }

limit colima status >/dev/null 2>&1 || exit 0   # 꺼져 있으면 쉰다
SOCK="$HOME/.colima/default/docker.sock"
if [ -S "$SOCK" ]; then DOCKER_HOST="unix://$SOCK"; export DOCKER_HOST; fi

# 볼륨을 만든 시각(RFC 3339: 2026-10-18T03:21:45Z · +09:00 처럼 시차가 붙기도 한다)을 초로 바꾼다
epoch_of() {
  perl -MTime::Local -e '
    $_ = shift;
    /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|([+-])(\d\d):?(\d\d))$/ or exit 1;
    $t = timegm($6, $5, $4, $3, $2 - 1, $1);
    $t -= ($8 eq "+" ? 1 : -1) * ($9 * 3600 + $10 * 60) if defined $8;
    print $t;' "$1"
}

CUTOFF=$(( $(date +%s) - MIN_AGE_H * 3600 ))
before=$(df -k / | awk 'NR==2{print $4}')

# 1) 빌드 캐시
if [ "$DRY" = "1" ]; then
  echo "  [dry] docker builder prune -af --filter until=${MIN_AGE_H}h"
elif ! limit docker builder prune -af --filter "until=${MIN_AGE_H}h" >/dev/null 2>&1; then
  echo "$(ts) ⚠ 빌드 캐시 정리 실패 — 건너뜀"
fi

# 2) 주인 없는 익명 볼륨
n=0
for v in $(limit docker volume ls -qf dangling=true 2>/dev/null); do
  case "$v" in *[!0-9a-f]*) continue ;; esac   # 이름 붙은 볼륨은 건너뛴다
  [ "${#v}" -eq 64 ] || continue
  created=$(limit docker volume inspect -f '{{.CreatedAt}}' "$v" 2>/dev/null) || continue
  c=$(epoch_of "$created") || continue
  [ "$c" -le "$CUTOFF" ] || continue
  if [ "$DRY" = "1" ]; then
    echo "  [dry] docker volume rm $v (만든 시각 $created)"
    continue
  fi
  # 그 사이 누가 붙였다면 docker 가 'in use' 로 거절한다 — 그대로 둔다
  limit docker volume rm "$v" >/dev/null 2>&1 && n=$((n + 1))
done

# 3) VM 안에서 지운 공간을 맥으로 돌려준다
if [ "$DRY" = "1" ]; then
  echo "  [dry] colima ssh -- sudo fstrim -a"
  exit 0
fi
if limit colima ssh -- sudo fstrim -a >/dev/null 2>&1; then
  sleep 3   # 반납한 공간이 맥 쪽 여유에 반영될 시간
else
  echo "$(ts) ⚠ fstrim 실패 — 건너뜀 (VM 안에서 지운 공간이 맥으로 돌아오지 않았을 수 있음)"
fi

after=$(df -k / | awk 'NR==2{print $4}')
echo "$(ts) 익명 볼륨 ${n}개 정리 · 맥 여유 변화 $(awk -v k=$((after - before)) 'BEGIN{printf "%+.2f GB", k/1048576}') · 여유 $(awk -v k="$after" 'BEGIN{printf "%dGB", k/1048576}')"
# 기록이 끝없이 길어지지 않게 — 400줄을 넘으면 뒤쪽 200줄만 남긴다
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 400 ]; then
  tail -200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG" || rm -f "$LOG.tmp"
fi
exit 0
