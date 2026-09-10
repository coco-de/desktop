#!/usr/bin/env bash
# ============================================================
# 우분투 초기 개발환경 세팅 스크립트
# 전제: 없음 — 필요한 패키지 저장소와 도구는 이 스크립트가 직접 등록·설치한다(0단계).
#
# 대상: Ubuntu 22.04 LTS 이상 / Debian 12 이상 (데스크톱)
#       x86_64(amd64) · ARM64 둘 다 지원한다.
#
# 실행 (레포를 clone한 경우): chmod +x linux-setup.sh && ./linux-setup.sh
# 실행 (clone 없이 한 줄로):
#   d="$(mktemp -d)" && curl -fsSL https://raw.githubusercontent.com/coco-de/co-linux/main/linux-setup.sh -o "$d/linux-setup.sh" && bash "$d/linux-setup.sh"
#   └ ⚠ 맥처럼 `bash -c "$(curl ...)"` 로 쓰면 안 된다. 리눅스 커널은 ARG_MAX 와 별개로
#     **인자 하나의 크기**를 128KiB(MAX_ARG_STRLEN)로 제한하는데 이 스크립트는 그보다 커서
#     "Argument list too long" 으로 실행 자체가 실패한다. (맥에는 그 제한이 없다)
#   └ 임시 폴더로 받는 방식이라 표준입력도 그대로 남아 3.2단계의 이메일 입력이 정상 동작하고,
#     옵션도 `-- ` 없이 그냥 뒤에 붙이면 된다: bash "$d/linux-setup.sh" --dart-only
#   └ 이 경우 스크립트 파일 하나만 내려오므로, 팀 셸 설정(.zshrc·.p10k.zsh)은
#     0.5단계에서 같은 레포에서 따로 내려받는다.
#   └ 이미 세팅한 PC에서 토큰(환경변수)만 다시 주입하려면: ./linux-setup.sh --env-only
#   └ Dart 글로벌 패키지만 다시 설치/업데이트하려면:      ./linux-setup.sh --dart-only
#   └ 그룹·권한 등 관리자 설정만 다시 잡으려면:           ./linux-setup.sh --system-only
#
# 기존 PC(맥 포함)의 테마/설정을 그대로 가져오려면, 기존 PC에서
#   ~/.zshrc, ~/.p10k.zsh
# 를 이 스크립트와 같은 폴더에 복사해 두세요. (있으면 레포 것 대신 그대로 사용)
#
# 형제 레포: coco-de/co-mac (macOS) · coco-de/co-win (Windows)
#            같은 도구 목록을 각 OS 방식으로 설치한다. 도구가 바뀌면 셋 다 갱신해야 한다.
# ============================================================
#
# [설치 단계 개요]
#   0.   apt 기본 구성 + 빌드 필수 패키지 (build-essential, curl, git, unzip 등)
#   0.5. 팀 셸 설정(.zshrc·.p10k.zsh) 확보 — 스크립트 옆에 둘 다 없으면 레포에서 내려받기
#   1.   GUI 앱 (Android Studio·Slack·Chrome·1Password·Tailscale·Orca·Lumide·Zed·Claude Desktop)
#   1.6. Chrome 확장 프로그램 자동 추가 (ZenHub for GitHub)
#   1.7. Pretendard 폰트 설치 (9개 스타일)
#   1.8. 1Password CLI(op) — 화면 없는 환경 보완 (1단계를 건너뛴 경우에만 동작)
#   2.   Claude Code CLI
#   2.5. Claude MCP (figma 플러그인 + zenhub·jira(mcp-atlassian)·slack 토큰 등록)
#   2.6. 다른 AI 코딩 CLI (codex=OpenAI · agy=Google Antigravity)
#   2.7. Slack CLI
#   3.   CLI 도구 (go·gh·jq·docker·direnv·openjdk-17·lefthook 등)
#   3.2. Git 사용자 이메일 (git config --global user.email, TTY면 입력·s로 건너뜀)
#   3.3. 브라우저 번역 언어 자동 설정 (Chrome → 한국어로 자동 번역)
#   3.4. GitHub 인증 자동화 (1Password 팀 공용 토큰 → gh auth login + gh auth setup-git)
#   3.5. cocode-skills 팀 플러그인 (사설 레포 install.sh, gh 인증 필요)
#   4.   Flutter/Dart(FVM) · Dart 글로벌 · gcloud · DCM · Android SDK/AVD
#   5.   Python (pyenv)
#   6.   Node.js (nvm)
#   6.1. codex 재시도 (2.6단계는 Node.js 이전이라 그때 건너뛴 경우)
#   6.5. Claude Code 상태줄 (ccstatusline)
#   7.   oh-my-zsh + powerlevel10k
#   7.5. 터미널 폰트 자동 적용 (MesloLGS NF — GNOME Terminal·Konsole)
#   8.   ~/.zshrc / ~/.p10k.zsh 반영 + 기본 셸을 zsh로 변경
#   8.5. ZENHUB_API_TOKEN 주입 (1Password op read → .zshrc)
#   8.6. JIRA_API_TOKEN 주입 (mcp-atlassian Docker MCP용)
#   8.7. SLANG_GPT_API_KEY 주입 (slang_gpt 다국어 자동 번역용)
#   8.8. DCM_EMAIL·DCM_CI_KEY 주입 (DCM CI 라이선스 인증용)
#   8.9. SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (slack MCP용)
#   9.   시스템 권한 — docker·kvm 그룹 가입, Android 기기 udev 규칙
#   10.  설치 검증 + 다음 단계 안내
# ============================================================
set -e

# ------------------------------------------------------------
# 실행 방식 감지 — 파일로 실행했나, curl 원라이너로 실행했나
#
#   파일로 실행하면(./linux-setup.sh · bash linux-setup.sh) BASH_SOURCE[0]에 그 경로가 들어온다.
#   원라이너(/bin/bash -c "$(curl ...)")로 실행하면 **빈 문자열**이 된다.
#
#   [왜 이걸 구분하나]
#   빈 문자열을 그대로 dirname에 넘기면 "."이 나오고, 결국 SCRIPT_DIR이 "지금 터미널이 열려
#   있는 폴더"(대개 홈 폴더)로 잡힌다. 홈 폴더에는 보통 .zshrc가 이미 있으므로,
#   8단계가 그 파일을 "스크립트 옆에 사용자가 놓아둔 설정"으로 착각해
#   `cp ~/.zshrc ~/.zshrc`(자기 자신을 자기 위에 복사)를 시도하고,
#   cp가 오류로 끝나면서 set -e에 걸려 스크립트 전체가 거기서 멈춰버린다.
#   → 원라이너에는 "옆 폴더"라는 개념 자체가 없으므로, 추측하지 말고 없다고 명시한다.
# ------------------------------------------------------------
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  STANDALONE=0
else
  SCRIPT_DIR=""
  STANDALONE=1   # curl 원라이너 — 옆에 놓인 파일이 없다고 본다
fi

# dotfile을 안전하게 복사한다 — 원본과 대상이 같은 파일이면 건너뛴다.
#   $1=원본  $2=대상  $3=사람이 읽을 이름
#   `-ef`는 두 경로가 같은 파일(같은 장치·inode)인지 보는 검사다. 심볼릭 링크로 이어진
#   경우까지 잡아내므로 경로 문자열 비교보다 안전하다.
#   원본이 없으면 1을 반환한다 (호출부가 "기본 설정 생성" 경로로 넘어갈 수 있게).
copy_dotfile() {
  local src="$1" dst="$2" name="$3"
  [[ -f "$src" ]] || return 1
  if [[ "$src" -ef "$dst" ]]; then
    echo "  ✓ $name 이미 제자리에 있음 (복사 생략)"
  else
    cp "$src" "$dst"
    echo "  ✓ $name 반영 완료"
  fi
}

# ------------------------------------------------------------
# 실행 옵션 파싱
#   (옵션 없음)   : 전체 설치 (0~10단계)
#   --env-only    : 1Password(op)에서 팀 공용 토큰만 다시 읽어 ~/.zshrc에 주입 (8.5~8.9단계만)
#   --dart-only   : Dart 글로벌 패키지만 다시 설치/업데이트 (4-b단계만)
#   --system-only : 관리자 권한이 필요한 시스템 설정만 다시 적용 (9단계만)
#   -h, --help    : 사용법 출력
#   모르는 옵션은 즉시 에러 종료한다 — 오탈자(예: --env-onyl)가 조용히
#   수십 분짜리 전체 설치로 이어지는 사고를 막기 위함이다.
# ------------------------------------------------------------
usage() {
  cat <<'USAGE'
사용법: ./linux-setup.sh [옵션]

  (옵션 없음)    co:code 팀 표준 개발환경 전체 설치 (0~10단계)
                 필요한 저장소·도구는 스크립트가 알아서 등록·설치합니다.
  --env-only     1Password(op)에서 팀 공용 토큰(ZENHUB_API_TOKEN·JIRA_API_TOKEN·
                 SLANG_GPT_API_KEY·DCM_EMAIL·DCM_CI_KEY·SLACK_TEAM_ID·
                 SLACK_BOT_TOKEN)만 다시 읽어 ~/.zshrc에 주입합니다.
                 앱/도구 설치 단계는 전부 건너뜁니다.
                 (토큰이 바뀌었거나, 설치 때 토큰 주입을 건너뛴 경우에 사용)
  --dart-only    Dart 글로벌 패키지(coverage·melos·mason_cli·flutter_gen·
                 jaspr_cli·serverpod_cli·flutterfire_cli·marionette_mcp·
                 mcp_server_dart·cob)만 다시 설치/업데이트합니다.
                 (팀 패키지 목록이 바뀌었거나, 패키지만 최신으로 올리고 싶을 때 사용
                  — Flutter/Dart(fvm)는 이미 설치돼 있어야 합니다)
  --system-only  관리자 권한이 필요한 설정만 다시 적용합니다 — docker·kvm 그룹 가입,
                 Android 기기 udev 규칙. 설치·토큰 주입 단계는 전부 건너뜁니다.
                 (설치 때 sudo 없이 돌렸거나, 도커·에뮬레이터 권한 오류가 날 때 사용)
  -h, --help     이 도움말을 표시합니다
USAGE
}

ENV_ONLY=0
DART_ONLY=0
SYSTEM_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --env-only)    ENV_ONLY=1 ;;
    --dart-only)   DART_ONLY=1 ;;
    --system-only) SYSTEM_ONLY=1 ;;
    -h|--help)     usage; exit 0 ;;
    *)
      echo "❌ 알 수 없는 옵션: $arg"
      echo ""
      usage
      exit 1
      ;;
  esac
done

# curl 한 줄 실행에서 `--` 를 빠뜨리면 bash -c 가 첫 인자를 $0(스크립트 이름)으로 먹어
#   옵션이 통째로 사라진다. 예: /bin/bash -c "$(curl …)" --dart-only → $0=--dart-only, $#=0
#   → 파싱 루프가 아무 옵션도 못 보고 **수십 분짜리 전체 설치가 조용히 시작된다.**
#   $0 가 옵션처럼 생겼다면 그 사고가 확실하므로, 설치를 시작하기 전에 멈추고 바른 형태를 보여준다.
#   ⚠ 바르게 `--` 를 붙여 실행하면 $0 는 `--` 자체가 된다(정상 경로) — 그건 걸러내면 안 되므로
#     `--?*`(-- 뒤에 글자가 더 있는 경우)와 `-h` 만 사고로 본다.
if [[ "$0" == --?* || "$0" == "-h" ]]; then
  echo "❌ 옵션이 스크립트에 전달되지 않았습니다: $0"
  echo ""
  echo "   임시 폴더로 받아 실행하는 방식을 쓰시면 옵션을 그냥 뒤에 붙이면 됩니다:"
  echo "   d=\"\$(mktemp -d)\" && curl -fsSL https://raw.githubusercontent.com/coco-de/co-linux/main/linux-setup.sh -o \"\$d/linux-setup.sh\" && bash \"\$d/linux-setup.sh\" $0"
  exit 1
fi

# 모드 옵션들은 하는 일이 서로 달라 함께 쓰면 어느 쪽을 원한 건지 알 수 없다 — 조용히
# 한쪽만 실행하지 말고 무엇을 골라야 하는지 알려주고 멈춘다.
#   (옵션이 하나 늘 때마다 조건을 새로 조합하지 않도록 개수로 센다)
MODE_COUNT=$(( ENV_ONLY + DART_ONLY + SYSTEM_ONLY ))
if (( MODE_COUNT > 1 )); then
  echo "❌ --env-only · --dart-only · --system-only 는 함께 쓸 수 없습니다 (하나씩 따로 실행해 주세요)"
  exit 1
fi

# ------------------------------------------------------------
# 공통 출력 헬퍼 — 모든 단계가 같은 모양으로 말하도록 한 곳에 모아 둔다.
# ------------------------------------------------------------
log()  { echo ""; echo "▶ $1"; }
have() { command -v "$1" >/dev/null 2>&1; }
ok()   { echo "  ✓ $1"; }
warn() { echo "  ⚠ $1"; }
info() { echo "     $1"; }

# ------------------------------------------------------------
# 배포판 확인 — Ubuntu 22.04+ / Debian 12+ 를 전제로 만들어졌다.
#   다른 배포판에서도 대부분 동작하지만 apt 저장소 이름이 달라 GUI 앱 단계가 실패할 수 있다.
#   그래도 멈추지는 않는다 — 경고만 하고 계속 진행해서, 되는 것만이라도 깔리게 한다.
# ------------------------------------------------------------
DISTRO_ID=""
DISTRO_CODENAME=""
DISTRO_VERSION=""
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-}"
  DISTRO_VERSION="${VERSION_ID:-}"
  # UBUNTU_CODENAME 은 우분투 파생(Mint 등)에서도 진짜 우분투 코드명을 담고 있어 더 안전하다.
  DISTRO_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
fi

if ! have apt-get; then
  echo "❌ apt-get 을 찾을 수 없습니다 — 이 스크립트는 Ubuntu/Debian 계열 전용입니다."
  echo "   (맥이라면 coco-de/co-mac, 윈도우라면 coco-de/co-win 을 사용해 주세요)"
  exit 1
fi

case "$DISTRO_ID" in
  ubuntu|debian|linuxmint|pop|elementary|zorin)
    : ;;   # 검증된/파생 배포판 — 그대로 진행
  *)
    echo ""
    echo "⚠ 확인되지 않은 배포판입니다: ${DISTRO_ID:-unknown} ${DISTRO_VERSION:-}"
    echo "  이 스크립트는 Ubuntu 22.04+ / Debian 12+ 에서 검증되었습니다."
    echo "  계속 진행하지만 일부 단계(특히 GUI 앱)가 실패할 수 있습니다."
    ;;
esac

# 코드명을 못 읽었으면 apt 저장소 등록에서 빈 문자열이 들어가 소스 목록이 깨진다.
#   현재 우분투 LTS 코드명으로 대신 채워 두고, 실패하면 그 단계만 건너뛰게 한다.
if [[ -z "$DISTRO_CODENAME" ]]; then
  DISTRO_CODENAME="jammy"
  warn "배포판 코드명을 읽지 못해 'jammy'로 가정합니다 (일부 저장소 등록이 실패할 수 있습니다)"
fi

# CPU 아키텍처 — apt 저장소 소스 라인과 직접 내려받는 tarball 이름에 쓴다.
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

# ------------------------------------------------------------
# 관리자 권한(sudo) 처리
#   root로 돌리면 sudo가 필요 없고, 일반 사용자면 sudo를 앞에 붙인다.
#   sudo 자체가 없거나 쓸 수 없으면 SUDO를 비워 두고 need_sudo가 거짓을 반환한다 —
#   그러면 관리자 권한이 필요한 단계는 "방법만 안내하고 건너뛴다".
#
#   ⚠ 스크립트 전체를 sudo로 돌리면 안 된다. fvm·dart pub global·nvm·pyenv 설치물이
#     전부 /root 밑에 깔려 평소 터미널에서 안 보이는 2차 사고가 난다.
#     (그래서 아래에서 root 실행을 감지하면 경고한다)
# ------------------------------------------------------------
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
  RUNNING_AS_ROOT=1
else
  SUDO="sudo"
  RUNNING_AS_ROOT=0
fi

# sudo를 실제로 쓸 수 있는지 확인한다. 쓸 수 있으면 0, 아니면 1.
#   결과를 SUDO_OK에 캐시해 단계마다 암호를 다시 묻지 않는다.
SUDO_OK=""
need_sudo() {
  if [[ -n "$SUDO_OK" ]]; then
    return "$SUDO_OK"
  fi
  if [[ "$RUNNING_AS_ROOT" -eq 1 ]]; then
    SUDO_OK=0
  elif ! have sudo; then
    SUDO_OK=1
  elif sudo -n true 2>/dev/null; then
    SUDO_OK=0            # 암호 없이 바로 가능 (NOPASSWD 또는 최근 인증됨)
  elif [[ -t 0 ]]; then
    # 대화형 터미널이면 한 번 물어본다. 여기서 실패하면 이후로는 계속 없다고 본다.
    echo ""
    echo "🔐 관리자 권한이 필요합니다 (패키지 설치·그룹 설정). 암호를 입력해 주세요."
    if sudo -v; then SUDO_OK=0; else SUDO_OK=1; fi
  else
    SUDO_OK=1            # 비대화형인데 암호가 필요하면 물어볼 방법이 없다
  fi
  return "$SUDO_OK"
}

if [[ "$RUNNING_AS_ROOT" -eq 1 ]]; then
  echo ""
  echo "⚠ root(또는 sudo)로 실행 중입니다."
  echo "  fvm·dart·nvm·pyenv 설치물이 /root 밑에 깔려 평소 사용자 터미널에서 보이지 않게 됩니다."
  echo "  일반 사용자로 './linux-setup.sh' 를 실행하는 것을 권장합니다 (필요할 때만 암호를 물어봅니다)."
  echo ""
fi

# ------------------------------------------------------------
# 데스크톱(GUI) 세션 여부
#   서버·컨테이너처럼 화면이 없는 환경에서는 GUI 앱 설치가 무의미하고 오래 걸리기만 한다.
#   HAS_GUI=0(있음) / 1(없음) — 1단계 전체와 1.6·1.7·7.5단계가 이 값을 본다.
# ------------------------------------------------------------
if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] || [[ -d /usr/share/xsessions ]] || have gnome-shell; then
  HAS_GUI=0
else
  HAS_GUI=1
fi

# ------------------------------------------------------------
# apt 헬퍼
#   apt-get update는 느려서 매번 돌리면 설치 시간이 눈에 띄게 늘어난다.
#   저장소를 새로 등록했을 때만 다시 돌도록 APT_STALE 로 관리한다.
# ------------------------------------------------------------
APT_STALE=1     # 1이면 다음 설치 전에 update가 필요하다는 뜻

apt_refresh() {
  [[ "$APT_STALE" -eq 0 ]] && return 0
  need_sudo || { warn "관리자 권한이 없어 apt 목록을 갱신하지 못했습니다"; return 1; }
  $SUDO apt-get update -qq || { warn "apt-get update 실패 → 계속 진행 (일부 패키지를 못 찾을 수 있습니다)"; }
  APT_STALE=0
  return 0
}

# 패키지가 이미 설치돼 있는지 확인 (설치됨 0)
is_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "^install ok installed$"
}

# 아직 없는 패키지만 골라 한 번에 설치한다.
#   이미 있는 건 apt에 넘기지 않아 출력이 조용하고, 하나가 실패해도 나머지는 살아남는다.
apt_install() {
  local pkg missing=()
  for pkg in "$@"; do
    if is_installed "$pkg"; then
      ok "$pkg 이미 설치됨"
    else
      missing+=("$pkg")
    fi
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  apt_refresh || return 1
  need_sudo || { warn "관리자 권한이 없어 설치를 건너뜁니다: ${missing[*]}"; return 1; }

  # 한 번에 시도하고, 통째로 실패하면 하나씩 다시 시도한다 —
  # 없는 패키지 이름 하나 때문에 나머지 열 개까지 못 깔 이유가 없다.
  if $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" </dev/null >/dev/null 2>&1; then
    for pkg in "${missing[@]}"; do ok "$pkg 설치 완료"; done
  else
    for pkg in "${missing[@]}"; do
      if $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" </dev/null >/dev/null 2>&1; then
        ok "$pkg 설치 완료"
      else
        warn "$pkg 설치 실패 → 건너뜀 (수동 설치: sudo apt install $pkg)"
      fi
    done
  fi
  return 0
}

# snap 패키지 설치. $1=이름, 나머지=추가 인자(--classic 등)
snap_install() {
  local name="$1"; shift
  if ! have snap; then
    warn "snap 이 없어 $name 설치를 건너뜁니다 (수동 설치: sudo apt install snapd)"
    return 1
  fi
  if snap list "$name" >/dev/null 2>&1; then
    ok "$name 이미 설치됨 (snap)"
    return 0
  fi
  need_sudo || { warn "관리자 권한이 없어 $name(snap) 설치를 건너뜁니다"; return 1; }
  $SUDO snap install "$name" "$@" >/dev/null 2>&1 \
    && ok "$name 설치 완료 (snap)" \
    || { warn "$name 설치 실패 → 건너뜀 (수동 설치: sudo snap install $name $*)"; return 1; }
  return 0
}

# 공식 apt 저장소를 등록한다 (멱등).
#   $1=이름(파일명에 쓰임)  $2=GPG 키 URL  $3=소스 라인의 저장소 부분
#   예: add_apt_repo google-chrome https://dl.google.com/linux/linux_signing_key.pub \
#         "https://dl.google.com/linux/chrome/deb/ stable main"
#   키는 /etc/apt/keyrings 에 두고 소스 라인에서 signed-by 로 지목한다
#   (apt-key 는 우분투 22.04부터 폐지 예고 상태라 쓰지 않는다).
add_apt_repo() {
  local name="$1" key_url="$2" repo_line="$3"
  local keyring="/etc/apt/keyrings/${name}.gpg"
  local list="/etc/apt/sources.list.d/${name}.list"

  if [[ -f "$keyring" && -f "$list" ]]; then
    ok "$name 저장소 이미 등록됨"
    return 0
  fi
  need_sudo || { warn "관리자 권한이 없어 $name 저장소 등록을 건너뜁니다"; return 1; }

  $SUDO install -d -m 0755 /etc/apt/keyrings || { warn "$name: keyrings 폴더 생성 실패"; return 1; }

  # 키가 ASCII armor(-----BEGIN PGP-----)일 수도, 이미 바이너리일 수도 있다.
  # gpg --dearmor 는 armor 형식만 받으므로, 실패하면 원본을 그대로 저장한다.
  local tmp_key
  tmp_key="$(mktemp)"
  if ! curl -fsSL "$key_url" -o "$tmp_key"; then
    rm -f "$tmp_key"
    warn "$name: GPG 키 내려받기 실패 → 저장소 등록 건너뜀"
    return 1
  fi
  if gpg --dearmor < "$tmp_key" 2>/dev/null | $SUDO tee "$keyring" >/dev/null && [[ -s "$keyring" ]]; then
    :
  else
    $SUDO cp "$tmp_key" "$keyring"
  fi
  rm -f "$tmp_key"
  $SUDO chmod 0644 "$keyring"

  echo "deb [arch=${ARCH} signed-by=${keyring}] ${repo_line}" | $SUDO tee "$list" >/dev/null \
    || { warn "$name: 소스 목록 작성 실패"; return 1; }

  APT_STALE=1     # 새 저장소가 생겼으니 다음 설치 전에 update가 필요하다
  ok "$name 저장소 등록 완료"
  return 0
}

# .deb 파일을 URL에서 직접 받아 설치한다 (공식 저장소가 없는 앱용).
#   $1=사람이 읽을 이름  $2=URL  $3=설치 확인용 명령 또는 dpkg 패키지명
install_deb() {
  local name="$1" url="$2" check="$3"
  if have "$check" || is_installed "$check"; then
    ok "$name 이미 설치됨"
    return 0
  fi
  need_sudo || { warn "관리자 권한이 없어 $name 설치를 건너뜁니다"; return 1; }

  local tmp_deb
  tmp_deb="$(mktemp --suffix=.deb)"
  if ! curl -fsSL "$url" -o "$tmp_deb"; then
    rm -f "$tmp_deb"
    warn "$name 내려받기 실패 → 건너뜀"
    return 1
  fi
  # apt-get install 로 설치하면 의존성까지 알아서 끌어온다 (dpkg -i 는 의존성에서 막힌다).
  if $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$tmp_deb" </dev/null >/dev/null 2>&1; then
    ok "$name 설치 완료"
  else
    warn "$name 설치 실패 → 건너뜀"
    rm -f "$tmp_deb"
    return 1
  fi
  rm -f "$tmp_deb"
  return 0
}

# 현재 세션 PATH 앞에 폴더를 추가한다 (중복 방지).
#   ~/.zshrc 반영은 8단계가 따로 하고, 이건 "지금 실행 중인 이 스크립트"가
#   방금 깐 도구를 바로 쓸 수 있게 하기 위한 것이다.
path_prepend() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  case ":$PATH:" in
    *":$dir:"*) : ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}

# ------------------------------------------------------------
# 1Password 관련 — 여러 단계(3.4 GitHub 인증 · 8.5~8.9 팀 토큰 주입)가 공유한다.
# 가장 먼저 쓰는 단계(3.4)보다 앞에 두어야 해서 여기 둔다.
# ------------------------------------------------------------
TEAM_OP_ACCOUNT="team-cocodeinc.1password.com"   # 팀 1Password 계정 (비밀 아님)

# op에 쓸 수 있는 계정이 등록돼 있는지 확인. 등록됨 0, 아니면 1.
#   ⚠ `op account list`는 계정이 하나도 없어도 종료코드 0에 빈 목록만 출력한다.
#     따라서 종료코드가 아니라 '출력 내용'으로 판단해야 한다.
op_has_account() {
  have op || return 1
  local accounts
  accounts="$(op account list 2>/dev/null || true)"
  [[ -n "$accounts" && "$accounts" != "[]" ]]
}

# 1Password에서 비밀값 하나를 읽어 표준출력으로 넘긴다. 실패하면 빈 문자열.
#   $1 = op:// 참조 (예: op://API Token/GitHub API Token/credential)
#   호출부는 결과가 비었는지로 성패를 판단한다.
op_read() {
  local ref="$1" value
  op_has_account || return 1
  value="$(op read "$ref" --account "$TEAM_OP_ACCOUNT" 2>/dev/null || true)"
  [[ -z "$value" ]] && value="$(op read "$ref" 2>/dev/null || true)"
  [[ -z "$value" ]] && return 1
  printf '%s' "$value"
  return 0
}

# ============================================================
# 0. apt 기반 구성 + 빌드 필수 패키지  /  0.5. 팀 셸 설정 확보
# ============================================================

# ------------------------------------------------------------
# 0. apt 기반 구성 + 빌드 필수 패키지
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   맥의 mac-setup.sh는 여기서 Homebrew(도구를 내려받아 깔아주는 프로그램)를 먼저 설치한다.
#   리눅스에는 Homebrew가 없어 생략 — 대체: 우분투/데비안에 기본으로 들어 있는 apt를 쓴다.
#   대신 apt가 아직 모르는 "무엇이 어디에 있는지 목록"을 한 번 갱신하고,
#   이후 단계들이 공통으로 필요로 하는 기본 재료(컴파일러·curl·git·압축 도구 등)를 깐다.
#   이 단계가 끝나야 3단계 CLI 도구, 4단계 Flutter, 1단계 GUI 앱이 제대로 깔린다.
#
#   [왜 여기서 한꺼번에 까나]
#   뒤 단계에서 하나씩 깔면 apt 목록 갱신이 여러 번 일어나 설치가 눈에 띄게 느려지고,
#   무엇이 빠져서 실패했는지도 흩어져서 알아보기 어렵다. 공통 재료는 맨 앞에서 한 번에
#   정리해 두고, 뒤 단계는 "이건 이미 있다"는 전제로 자기 일만 하게 한다.
#
#   [실패해도 멈추지 않는다]
#   배포판·버전마다 패키지 이름이 조금씩 다르다(예: libasound2 → 우분투 24.04부터 libasound2t64).
#   공통 헬퍼 apt_install이 한 번에 시도한 뒤 실패하면 하나씩 다시 시도하므로,
#   이름이 없는 패키지 한둘 때문에 나머지가 통째로 빠지는 일은 없다.
#   관리자 권한(sudo)이 없으면 설치는 건너뛰고 안내만 남긴다.
# ------------------------------------------------------------
if (( ENV_ONLY || DART_ONLY || SYSTEM_ONLY )); then
  # --env-only는 op만, --dart-only는 이미 깔린 dart만, --system-only는 기본 시스템 명령만
  # 쓰므로 새로 깔 기반 패키지가 없다 — 이 단계를 통째로 건너뛴다.
  :
else
  log "0. apt 기본 구성 + 빌드 필수 패키지 설치"
  echo "  · 패키지 목록을 갱신한 뒤, 이후 단계가 공통으로 쓰는 기본 도구를 설치합니다"
  echo "  · 처음 실행이라면 몇 분 걸릴 수 있습니다 (관리자 암호를 한 번 물어볼 수 있습니다)"

  # 저장소 목록 갱신 — 실패해도 경고만 남기고 계속 간다 (헬퍼가 알아서 처리).
  apt_refresh || warn "apt 목록 갱신에 실패했습니다 → 계속 진행 (일부 패키지를 못 찾을 수 있습니다)"

  # (1) 빌드·다운로드 기본 재료
  #     build-essential = gcc·g++·make 묶음. 맥의 Xcode Command Line Tools에 해당한다.
  #     ca-certificates·gnupg·apt-transport-https는 뒤 단계에서 구글·도커 같은 공식 저장소를
  #     HTTPS로 등록할 때 필요하고, software-properties-common은 add-apt-repository를 제공한다.
  #     jq는 3·8단계에서 JSON 응답을 다룰 때, zsh는 7·8단계(oh-my-zsh·기본 셸 변경)에서 쓴다.
  BASE_PKGS=(
    build-essential curl wget git unzip zip xz-utils file
    ca-certificates gnupg apt-transport-https software-properties-common
    jq zsh
  )
  apt_install "${BASE_PKGS[@]}" || warn "기본 패키지 일부를 설치하지 못했습니다 → 계속 진행"

  # (2) Flutter 리눅스 데스크톱 빌드용
  #     맥에서는 Xcode가 해주던 일을 리눅스에서는 clang·cmake·ninja·GTK 개발 파일이 나눠 맡는다.
  #     이게 없으면 `flutter doctor`가 "linux toolchain" 항목에서 ✗ 를 띄우고,
  #     4단계에서 리눅스 데스크톱 앱 빌드가 실패한다.
  #     libstdc++-12-dev는 배포판에 따라 이름이 없을 수 있다 — 그러면 그 하나만 건너뛴다.
  FLUTTER_BUILD_PKGS=(
    clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev "libstdc++-12-dev"
  )
  apt_install "${FLUTTER_BUILD_PKGS[@]}" || warn "Flutter 데스크톱 빌드 패키지 일부를 설치하지 못했습니다 → 계속 진행"

  # (3) Android SDK·에뮬레이터가 요구하는 그래픽·사운드 라이브러리
  #     이게 빠지면 4단계에서 만든 에뮬레이터(AVD)가 실행되다가 조용히 죽거나 소리가 안 난다.
  #     ⚠ 소리 라이브러리는 우분투 24.04부터 이름이 libasound2 → libasound2t64로 바뀌었다.
  #       어느 쪽이 맞는지 배포판마다 달라 **둘 다 목록에 넣는다** — 없는 쪽 하나는
  #       "설치 실패 → 건너뜀" 경고가 뜨지만 정상이며, 맞는 쪽이 깔렸으면 문제없다.
  echo "  · (아래에서 libasound2 / libasound2t64 중 한쪽은 '설치 실패'가 뜹니다 — 정상입니다)"
  ANDROID_RUNTIME_PKGS=(
    libpulse0 libnss3 libxcursor1 libxdamage1 libxrandr2 libxcomposite1
    libasound2t64 libasound2
  )
  apt_install "${ANDROID_RUNTIME_PKGS[@]}" || warn "Android 실행 라이브러리 일부를 설치하지 못했습니다 → 계속 진행"

  # (4) snapd — 1단계 GUI 앱(안드로이드 스튜디오·Slack 등) 상당수를 snap으로 설치한다.
  #     우분투 데스크톱에는 기본으로 들어 있지만, 데비안이나 최소 설치본에는 없을 수 있다.
  if have snap; then
    ok "snap 이미 사용 가능"
  else
    echo "  · snap이 없습니다 → 1단계 GUI 앱 설치에 필요해 함께 설치합니다"
    apt_install snapd || warn "snapd 설치 실패 → 1단계에서 snap으로 까는 앱들은 건너뛰게 됩니다"
  fi
  # 방금 깐 snapd의 앱 경로를 현재 세션 PATH에 넣어 둔다 (~/.zshrc 반영은 8단계가 한다).
  path_prepend "/snap/bin"

  # ---- 결과 요약 ----
  #   "무엇이 깔렸다"보다 "이후 단계가 돌아갈 준비가 됐나"를 알려주는 게 팀원에게 유용하다.
  MISSING_CORE=()
  for _core_cmd in gcc make curl wget git unzip jq zsh; do
    have "$_core_cmd" || MISSING_CORE+=("$_core_cmd")
  done

  if [[ ${#MISSING_CORE[@]} -eq 0 ]]; then
    ok "빌드 기본 도구 준비 완료 (gcc·make·curl·wget·git·unzip·jq·zsh)"
  else
    warn "기본 도구가 아직 없습니다: ${MISSING_CORE[*]} → 계속 진행하지만 뒤 단계가 실패할 수 있습니다"
    info "수동 설치: sudo apt install ${MISSING_CORE[*]}"
  fi

  if pkg-config --exists gtk+-3.0 2>/dev/null; then
    ok "Flutter 리눅스 데스크톱 빌드 재료 준비 완료 (clang·cmake·ninja·GTK3)"
  else
    warn "GTK3 개발 파일을 찾지 못했습니다 → 리눅스 데스크톱 앱 빌드만 안 될 수 있습니다 (모바일/웹은 정상)"
    info "수동 설치: sudo apt install libgtk-3-dev pkg-config clang cmake ninja-build"
  fi

  unset MISSING_CORE _core_cmd BASE_PKGS FLUTTER_BUILD_PKGS ANDROID_RUNTIME_PKGS
fi

# ------------------------------------------------------------
# 0.5. 팀 셸 설정(.zshrc · .p10k.zsh) 확보
#
#   [왜 필요한가]
#   8단계는 이 스크립트 옆에 있는 .zshrc / .p10k.zsh를 그대로 복사해 팀 공통 셸 설정과
#   터미널 프롬프트 테마를 맞춘다. 그런데 레포를 clone하지 않고 아래처럼 한 줄로 실행하면
#     /bin/bash -c "$(curl -fsSL .../linux-setup.sh)"
#   스크립트 파일 하나만 내려오기 때문에 그 두 파일이 옆에 없다. 그대로 두면 8단계가
#   '기본 설정 생성' 경로로 빠져서, 설치는 성공한 것처럼 보이지만 팀과 다른 셸 환경이
#   만들어진다. → 옆에 없으면 같은 레포에서 직접 내려받아 팀 설정을 그대로 유지한다.
#
#   [둘 다 없을 때만 받는 이유]
#   기존 PC(맥 포함)에서 쓰던 .zshrc만 옆에 복사해 두는 사용법(파일 상단 안내)을 존중하기
#   위함이다. 하나라도 옆에 있으면 사용자가 의도적으로 가져온 것으로 보고 건드리지 않는다.
#   단, 원라이너(STANDALONE)에는 '옆 폴더'라는 개념이 없으므로 이 판단을 아예 하지 않고
#   항상 받는다 — 예전에는 이때 홈 폴더를 옆 폴더로 착각해, 사용자의 기존 ~/.zshrc를
#   '가져온 설정'으로 오인하고 팀 설정을 건너뛰는 문제가 있었다.
#
#   내려받기에 실패해도 중단하지 않는다 — 8단계의 기본 설정 생성 경로로 자연히 넘어간다.
# ------------------------------------------------------------
REPO_RAW_BASE="https://raw.githubusercontent.com/coco-de/co-linux/main"
# 8단계가 참조할 dotfile 위치. 기본은 스크립트 옆이고, 원라이너 실행이면 임시 폴더로 바뀐다.
DOTFILE_DIR="$SCRIPT_DIR"

if (( ! ENV_ONLY && ! DART_ONLY && ! SYSTEM_ONLY )) \
   && { (( STANDALONE )) || [[ ! -f "$SCRIPT_DIR/.zshrc" && ! -f "$SCRIPT_DIR/.p10k.zsh" ]]; }; then
  log "0.5. 팀 셸 설정(.zshrc · .p10k.zsh) 내려받기"
  echo "  · 스크립트 옆에 설정 파일이 없습니다 (clone 없이 한 줄로 실행한 경우) → 레포에서 직접 받습니다"

  if ! have curl; then
    # 0단계에서 curl 설치가 실패한 경우 — 여기서 멈추지 말고 8단계에 맡긴다.
    warn "curl이 없어 팀 셸 설정을 내려받지 못했습니다 → 8단계에서 기본 설정으로 대체됩니다"
  else
    DOTFILE_DIR="$(mktemp -d)"
    for dotfile in .zshrc .p10k.zsh; do
      if curl -fsSL "$REPO_RAW_BASE/$dotfile" -o "$DOTFILE_DIR/$dotfile"; then
        ok "$dotfile 내려받음"
      else
        rm -f "$DOTFILE_DIR/$dotfile"
        warn "$dotfile 내려받기 실패 → 건너뜀 (8단계에서 기본 설정으로 대체)"
      fi
    done
    info "받은 파일 위치: $DOTFILE_DIR (8단계가 여기서 ~/ 로 복사합니다)"
  fi
fi

# ============================================================
# 아래 두 묶음은 "함수 정의"다 — 모드 옵션(--dart-only·--system-only)이 설치 본문을
# 건너뛰고 곧바로 부를 수 있어야 해서, 실제로 쓰이는 자리(4-b·9단계)보다 앞에 둔다.
# ============================================================

# ============================================================
# 4. Flutter/Dart 및 SDK 일괄
#    4-a FVM+Flutter · 4-b Dart 글로벌 패키지 · 4-c gcloud · 4-d DCM · 4-e Android SDK/AVD
# ============================================================

# ============================================================
# 4-b단계(Dart 글로벌 패키지) 본체
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   Flutter/Dart로 일할 때 터미널에서 바로 부르는 도구들(테스트 커버리지 측정, 모노레포
#   관리, 코드 템플릿 생성 등)을 컴퓨터 전체에서 쓸 수 있게 깔아 둔다. 프로젝트마다
#   따로 까는 게 아니라 PC에 한 번 깔아 두고 모든 프로젝트에서 함께 쓰는 도구들이다.
#
#   기본 패키지 — 팀 Makefile의 `make pub_global`과 같은 목록이라, 프로젝트를 받자마자
#     바로 빌드·코드생성·테스트를 돌릴 수 있다:
#     coverage · melos · mason_cli · flutter_gen · jaspr_cli · serverpod_cli · flutterfire_cli
#   co:code 추가분 — Claude Code가 쓰는 MCP 서버와 사내 스캐폴딩 CLI:
#     marionette_mcp · mcp_server_dart · cob(co-bricks)
#
#   [정의를 여기 둔 이유]
#   --dart-only 는 설치 단계를 전부 건너뛰고 이 단계만 실행하고, 10단계 검증도 아래
#   print_dart_packages_verification 을 그대로 다시 쓴다. 두 곳이 같은 기준으로 판정하도록
#   본체를 함수로 뽑아 두었다. 실제 호출은 (전체 실행 시) 아래 4-b 위치에서 한다.
# ============================================================

# dart 와 전역 패키지 실행 파일을 찾을 수 있게 PATH를 잡는다. 여러 번 불러도 안전하다.
dart_prepare_path() {
  export PUB_CACHE="$HOME/.pub-cache"
  local dir rest
  # fvm 기본 버전(4-a에서 지정)의 dart 를 PATH '맨 앞'으로 끌어온다.
  #   ⚠ "dart 가 없을 때만" 얹으면 안 된다 — apt·snap 으로 깔린 dart 나 Android Studio 번들처럼
  #     **다른** dart 가 앞에 있으면 Flutter SDK가 딸리지 않은 그 dart로 패키지를 깔게 되고,
  #     flutter_gen·flutterfire_cli 같은 Flutter 의존 패키지가 알아보기 어려운 에러로 실패한다.
  #     그래서 이미 PATH에 있더라도 한 번 빼고 다시 맨 앞에 붙인다.
  #     (전체 실행의 4-a도 같은 경로를 그대로 앞에 얹으므로 동작이 서로 어긋나지 않는다.)
  #   목록 순서상 뒤에 오는 것이 최종적으로 더 앞에 놓인다 → pub-cache/bin, fvm/default/bin 순.
  for dir in "$HOME/.fvm_flutter/bin" "$HOME/fvm/bin" "$HOME/fvm/default/bin" "$PUB_CACHE/bin"; do
    [[ -d "$dir" ]] || continue
    rest=":$PATH:"
    rest="${rest//:$dir:/:}"   # 기존 항목 제거
    rest="${rest#:}"           # 앞뒤 구분자 정리
    rest="${rest%:}"
    export PATH="$dir${rest:+:$rest}"
  done
}

run_dart_packages_step() {
  dart_prepare_path
  log "4-b. Dart 글로벌 패키지 설치 (coverage, melos, mason_cli, flutter_gen, jaspr_cli, serverpod_cli, flutterfire_cli + marionette_mcp, mcp_server_dart, cob)"
  # 버전을 고정하지 않는 기본 패키지들은 한 번에 돌린다.
  #   dart pub global activate는 이미 설치돼 있어도 최신으로 다시 활성화만 하므로 여러 번 실행해도 안전하다.
  for pkg in coverage melos mason_cli flutter_gen jaspr_cli; do
    dart pub global activate "$pkg" || warn "$pkg 설치 실패 → 건너뜀"
  done
  # serverpod_cli만 버전 제약이 붙는다 — ^4.0.0-beta.4는 "4.0.0-beta.4 이상 5.0.0 미만"이라
  # 4.x 베타 안에서는 최신을 따라가되 5.0 메이저로는 자동으로 넘어가지 않는다.
  dart pub global activate serverpod_cli '^4.0.0-beta.4' || warn "serverpod_cli 설치 실패 → 건너뜀"
  # flutterfire_cli: pub.dev 공개 패키지라 cob과 달리 GitHub 인증 없이 바로 설치된다
  dart pub global activate flutterfire_cli || warn "flutterfire_cli 설치 실패 → 건너뜀"
  # 여기부터는 co:code 추가분 (위 기본 목록에는 없다)
  dart pub global activate marionette_mcp || warn "marionette_mcp 설치 실패 → 건너뜀"
  dart pub global activate mcp_server_dart || warn "mcp_server_dart 설치 실패 → 건너뜀"
  # cob(co-bricks)는 비공개 레포라 순수 git 인증이 필요하다 — gh 인증(전체 실행이면 3.4단계에서
  # 1Password로 자동 로그인 시도) 상태를 먼저 확인해, 안 돼 있으면 원인을 알 수 있는 안내로 대신한다.
  # (인증 없이 그대로 시도하면 git이 사용자 이름/암호를 물어보다 알아보기 어려운 원문 에러로 실패한다.)
  if have gh && gh auth status >/dev/null 2>&1; then
    # GIT_TERMINAL_PROMPT=0: git 이 자격증명을 못 찾아도 사용자 이름/암호를 물어보며 멈추지
    #   않게 한다. gh 로그인은 돼 있지만 `gh auth setup-git`(3.4단계)이 안 된 PC에서 실제로
    #   입력 대기에 걸려 스크립트가 멈춘 것처럼 보이는 일이 있다 — 물어보는 대신 바로 실패시킨다.
    GIT_TERMINAL_PROMPT=0 dart pub global activate --source git https://github.com/coco-de/co-bricks.git \
      || { warn "cob(co-bricks) 설치 실패 → 건너뜀"
           info "(git 자격증명이 없을 수 있습니다 — 'gh auth setup-git' 실행 후 다시 시도해 주세요)"; }
  else
    warn "GitHub 인증이 안 돼 있어 cob(co-bricks) 설치를 건너뜁니다"
    info "(gh가 없거나 아직 로그인 전입니다 — 'gh auth login' 을 마친 뒤 다시 실행해 주세요."
    info " 전체 설치라면 3.4단계가 1Password로 자동 로그인을 시도합니다)"
  fi
  return 0
}

# 10단계 검증과 --dart-only 마무리가 같이 쓰는 Dart 패키지 확인 출력.
#   두 곳에서 같은 기준으로 판정해야 해서 한 군데(여기)만 고치면 되도록 함수로 뽑아 두었다.
#   판정 결과(빠진 패키지 이름들)는 DART_PACKAGES_MISSING 에 남겨, 부른 쪽이 마무리 문구를
#   고를 수 있게 한다 — 하나도 못 깔았는데 '완료'라고 말하지 않기 위함이다.
print_dart_packages_verification() {
  dart_prepare_path
  local dart_list base_missing="" pkg
  dart_list=$(dart pub global list 2>/dev/null || true)

  # 기본 패키지는 개수가 많아 한 줄로 묶고, 빠진 것만 이름으로 알려준다
  #   (목록 조회는 한 번만 하고 그 결과를 재사용한다 — 패키지마다 다시 부르면 그만큼 느려진다)
  for pkg in coverage melos mason_cli flutter_gen jaspr_cli serverpod_cli; do
    echo "$dart_list" | grep -q "^$pkg " || base_missing="$base_missing $pkg"
  done
  echo "  dart 기본 패키지: $([[ -z "$base_missing" ]] \
    && echo '✓ coverage, melos, mason_cli, flutter_gen, jaspr_cli, serverpod_cli' \
    || echo "❌ 누락:$base_missing ('./linux-setup.sh --dart-only' 로 이 단계만 다시 실행할 수 있습니다)")"
  DART_PACKAGES_MISSING="$base_missing"

  # marionette_mcp 는 pub 목록이 아니라 실행 파일 존재로 판정한다 (기존 검증과 같은 기준)
  if [[ -x "$PUB_CACHE/bin/marionette_mcp" ]]; then
    echo "  marionette: ✓"
  else
    echo "  marionette: ❌"
    DART_PACKAGES_MISSING="$DART_PACKAGES_MISSING marionette_mcp"
  fi
  if echo "$dart_list" | grep -q '^mcp_server_dart '; then
    echo "  mcp_server_dart: ✓"
  else
    echo "  mcp_server_dart: ❌"
    DART_PACKAGES_MISSING="$DART_PACKAGES_MISSING mcp_server_dart"
  fi
  if echo "$dart_list" | grep -q '^flutterfire_cli '; then
    echo "  flutterfire_cli: ✓"
  else
    echo "  flutterfire_cli: ❌"
    DART_PACKAGES_MISSING="$DART_PACKAGES_MISSING flutterfire_cli"
  fi
  if echo "$dart_list" | grep -q '^cob '; then
    echo "  cob(co-bricks): ✓"
  else
    echo "  cob(co-bricks): ❌ (위 GitHub 인증(gh) 확인 후 재실행)"
    DART_PACKAGES_MISSING="$DART_PACKAGES_MISSING cob"
  fi
}

# ============================================================
# 8 · 8.5~8.9 · 9 · 10 — 셸 설정 반영 / 팀 토큰 주입 / 시스템 권한 / 검증
#   8.   ~/.zshrc · ~/.p10k.zsh 반영 (+ 맥 경로 → 리눅스 경로 변환, 기본 셸을 zsh로)
#   8.5~8.9 1Password 팀 공용 토큰 5종 주입 (ZENHUB · JIRA · SLANG_GPT · DCM · SLACK)
#   8.10 --env-only 마무리
#   9.   시스템 권한 — docker·kvm 그룹 가입, 안드로이드 기기 udev 규칙
#   10.  설치 검증 + 다음 단계 안내
# ============================================================

# ------------------------------------------------------------
# 9단계 본체를 먼저 정의해 둔다.
#   --system-only 는 설치·토큰 주입을 전부 건너뛰고 이 단계만 실행하므로,
#   실제 호출 위치(아래 9단계)보다 앞에서 정의돼 있어야 한다.
#   (맥 스크립트가 --perms-only 를 위해 권한 단계를 앞쪽에 정의해 둔 것과 같은 이유)
#
#   [리눅스에서 '시스템 권한'이 뜻하는 것]
#   맥은 '전체 디스크 접근' 같은 앱 권한을 시스템 설정에서 켜야 하지만, 리눅스에서 개발에
#   실제로 걸리는 것은 대부분 '그룹'과 'USB 장치 규칙'이다.
#     · docker 그룹  : 없으면 docker 명령마다 sudo 를 붙여야 한다
#     · kvm 그룹     : 없으면 안드로이드 에뮬레이터가 가속을 못 써서 매우 느리다
#     · udev 규칙    : 없으면 USB로 연결한 안드로이드 실기기가 adb 에서 'no permissions' 로 뜬다
# ------------------------------------------------------------

# 그룹 가입 등으로 '재로그인이 필요한 변경'이 있었는지 표시한다 (10단계 안내에서 사용).
NEED_RELOGIN=0

# 현재 사용자가 어떤 그룹에 속해 있는지 확인 (속해 있으면 0)
in_group() {
  case " $(id -nG 2>/dev/null) " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

# 한 그룹에 현재 사용자를 넣는다. $1=그룹명  $2=사람이 읽을 설명
#   이미 속해 있으면 아무것도 하지 않는다(멱등). 관리자 권한이 없으면 명령만 안내한다.
join_group() {
  local grp="$1" why="$2" me
  me="$(id -un)"

  if ! getent group "$grp" >/dev/null 2>&1; then
    warn "$grp 그룹이 시스템에 없어 가입을 건너뜁니다 ($why)"
    info "해당 도구 설치가 끝나면 그룹이 생깁니다 — 그 뒤 './linux-setup.sh --system-only' 를 실행해 주세요"
    return 1
  fi
  if in_group "$grp"; then
    ok "$grp 그룹에 이미 가입돼 있습니다"
    return 0
  fi
  if ! need_sudo; then
    warn "관리자 권한이 없어 $grp 그룹 가입을 건너뜁니다 ($why)"
    info "수동 실행: sudo usermod -aG $grp $me   (실행 후 로그아웃/로그인해야 적용됩니다)"
    return 1
  fi
  if $SUDO usermod -aG "$grp" "$me" 2>/dev/null; then
    ok "$grp 그룹 가입 완료 ($why)"
    NEED_RELOGIN=1
    return 0
  fi
  warn "$grp 그룹 가입 실패 → 건너뜀 (수동 실행: sudo usermod -aG $grp $me)"
  return 1
}

# 안드로이드 실기기(USB 디버깅)용 udev 규칙을 넣는다.
#   1순위: android-sdk-platform-tools-common 패키지 — 구글이 관리하는 최신 벤더 목록이 통째로 들어온다.
#   2순위: 패키지를 못 구하면 자주 쓰는 제조사만 담은 규칙 파일을 직접 만든다.
install_android_udev_rules() {
  local rules="/etc/udev/rules.d/51-android.rules"

  # 이미 어느 쪽으로든 규칙이 들어와 있으면 건드리지 않는다 (멱등)
  if is_installed android-sdk-platform-tools-common || [[ -f "$rules" ]]; then
    ok "안드로이드 기기 USB 규칙 이미 적용됨"
    return 0
  fi
  if ! need_sudo; then
    warn "관리자 권한이 없어 안드로이드 기기 USB 규칙을 건너뜁니다"
    info "수동 실행: sudo apt install android-sdk-platform-tools-common"
    info "           (그 뒤 sudo udevadm control --reload-rules && sudo udevadm trigger)"
    return 1
  fi

  # 1순위 — 공식 패키지
  apt_install android-sdk-platform-tools-common || true
  if is_installed android-sdk-platform-tools-common; then
    reload_udev_rules
    return 0
  fi

  # 2순위 — 직접 작성 (패키지가 없는 배포판/버전 대비)
  warn "android-sdk-platform-tools-common 패키지를 구하지 못해 규칙 파일을 직접 만듭니다"
  if $SUDO tee "$rules" >/dev/null <<'ANDROID_RULES'
# co:code linux-setup.sh 가 생성한 안드로이드 기기 USB 규칙
#   USB로 연결한 실기기를 adb 가 관리자 권한 없이 인식하게 해 준다.
#   (이 규칙이 없으면 `adb devices` 에 기기가 "no permissions" 로 뜬다)
#   MODE="0664" + GROUP="plugdev" = plugdev 그룹에 속한 사용자가 기기에 접근 가능
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="2717", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="2a70", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="22d9", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="2d95", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="1004", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0502", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0664", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="1949", MODE="0664", GROUP="plugdev"
ANDROID_RULES
  then
    $SUDO chmod 0644 "$rules" 2>/dev/null || true
    ok "안드로이드 기기 USB 규칙 작성 완료 ($rules)"
    reload_udev_rules
    return 0
  fi
  warn "안드로이드 기기 USB 규칙 작성 실패 → 건너뜀 (수동 설치: sudo apt install android-sdk-platform-tools-common)"
  return 1
}

# 새로 넣은 udev 규칙을 지금 바로 적용한다 (재부팅 없이 반영).
reload_udev_rules() {
  have udevadm || { warn "udevadm 이 없어 규칙 즉시 적용을 건너뜁니다 (기기를 다시 꽂거나 재부팅하면 적용됩니다)"; return 1; }
  need_sudo || return 1
  if $SUDO udevadm control --reload-rules >/dev/null 2>&1 && $SUDO udevadm trigger >/dev/null 2>&1; then
    ok "USB 규칙 즉시 적용 완료 (기기를 다시 꽂으면 인식됩니다)"
  else
    warn "USB 규칙 즉시 적용 실패 → 기기를 다시 꽂거나 재부팅하면 적용됩니다"
  fi
  return 0
}

run_system_permission_step() {
  log "9. 시스템 권한 설정 (docker·kvm 그룹, 안드로이드 기기 USB 규칙)"

  # ── docker 그룹 ────────────────────────────────────────────
  # 가입하지 않으면 docker 명령마다 sudo 를 붙여야 하고, Claude Code 안에서 도는
  # jira MCP(도커 컨테이너)도 뜨지 않는다.
  if have docker || is_installed docker.io || is_installed docker-ce; then
    join_group docker "sudo 없이 docker 명령을 쓰기 위함" || true
  else
    warn "docker 가 설치돼 있지 않아 그룹 가입을 건너뜁니다"
    info "3단계에서 docker 설치가 실패한 경우입니다 — 설치 후 './linux-setup.sh --system-only' 를 실행해 주세요"
  fi

  # ── kvm 그룹 ───────────────────────────────────────────────
  # 안드로이드 에뮬레이터는 CPU 가상화(KVM)를 써야 실사용 가능한 속도가 나온다.
  # /dev/kvm 이 없는 PC(가상머신 안이거나 BIOS에서 가상화가 꺼진 경우)에서는 할 일이 없다.
  if [[ -e /dev/kvm ]]; then
    join_group kvm "안드로이드 에뮬레이터 하드웨어 가속(KVM)에 필요" || true
  else
    warn "/dev/kvm 이 없어 kvm 그룹 가입을 건너뜁니다"
    info "이 PC에서는 안드로이드 에뮬레이터가 매우 느립니다 — BIOS/UEFI 에서 가상화(VT-x/AMD-V)를 켜면 해결됩니다"
    info "(가상머신 안에서 실행 중이라면 중첩 가상화를 켜야 합니다 · 실기기 USB 디버깅은 그대로 사용할 수 있습니다)"
  fi

  # ── plugdev 그룹 + 안드로이드 기기 USB 규칙 ────────────────
  # udev 규칙이 기기 접근 권한을 plugdev 그룹에 주므로, 그룹 가입도 함께 해 둔다.
  if getent group plugdev >/dev/null 2>&1; then
    join_group plugdev "USB로 연결한 안드로이드 실기기 접근에 필요" || true
  fi
  install_android_udev_rules || true

  # 그룹은 '로그인할 때' 읽히기 때문에, 지금 열려 있는 터미널에는 절대 반영되지 않는다.
  # 이걸 모르면 "스크립트가 성공했다는데 docker 가 여전히 permission denied" 로 헤매게 된다.
  if (( NEED_RELOGIN )); then
    echo ""
    echo "  ❗ 그룹 변경은 '다시 로그인'해야 적용됩니다."
    echo "     지금 열려 있는 터미널·앱에는 반영되지 않습니다 — 로그아웃했다 다시 로그인하거나(권장),"
    echo "     재부팅한 뒤에 docker·에뮬레이터를 사용해 주세요."
    echo "     (지금 당장 확인만 해보고 싶다면: newgrp docker  ← 그 터미널 한 곳에만 임시로 적용됩니다)"
  fi
}

# --system-only: 설치·토큰 주입·검증을 건너뛰고 9단계만 실행하고 끝낸다.
if (( SYSTEM_ONLY )); then
  run_system_permission_step
  echo ""
  echo "✅ 시스템 권한 점검 완료 (전체 설치는 옵션 없이 './linux-setup.sh' 실행)"
  exit 0
fi

# --dart-only: 설치·토큰 주입·권한 점검을 전부 건너뛰고 4-b(Dart 글로벌 패키지)만 실행한다.
#   Flutter/Dart(fvm)까지 대신 깔아주지는 않는다 — 그건 전체 설치가 할 일이고, 여기서 함께
#   하면 "패키지만 업데이트"라는 이 옵션의 약속이 깨진다. dart가 없으면 안내하고 멈춘다.
if (( DART_ONLY )); then
  dart_prepare_path
  if ! have dart; then
    echo ""
    if have fvm; then
      # fvm 은 있는데 기본 버전이 지정되지 않은 PC — 4-a의 `fvm global stable` 이 예전 실행에서
      # ⚠ 로 건너뛰어진 경우다. 여기서 대신 깔아주지 않고 복붙할 명령을 그대로 알려준다.
      echo "❌ dart 명령을 찾지 못했습니다 — fvm은 있지만 기본 Flutter 버전이 지정돼 있지 않습니다."
      echo "   → 아래를 먼저 실행한 뒤 다시 시도해 주세요:"
      echo "        fvm global stable"
      echo "        ./linux-setup.sh --dart-only"
    else
      echo "❌ dart 명령을 찾지 못했습니다 — Flutter/Dart(fvm)가 아직 준비되지 않은 PC로 보입니다."
      echo "   이 옵션은 이미 세팅을 마친 PC에서 '패키지만' 다시 까는 용도라 전체 설치가 먼저입니다."
      echo "   → 옵션 없이 실행해 주세요: ./linux-setup.sh"
    fi
    exit 1
  fi
  # 어떤 dart 로 깔고 있는지 한 줄 남긴다 — apt·snap·Android Studio 번들이 섞여 있을 때
  # "왜 어떤 패키지만 실패하지?" 를 이 한 줄로 바로 알 수 있다.
  echo "  · 사용 중인 dart: $(command -v dart)"
  run_dart_packages_step
  log "Dart 글로벌 패키지 업데이트 결과 (--dart-only)"
  print_dart_packages_verification
  echo ""
  if [[ -z "${DART_PACKAGES_MISSING:-}" ]]; then
    echo "✅ 완료! (전체 설치는 옵션 없이 './linux-setup.sh' 실행)"
    echo "   방금 깔린 명령들은 ~/.pub-cache/bin 에 있습니다 — 새 터미널에서 바로 쓸 수 있습니다."
  else
    # 하나라도 빠졌으면 '완료' 배너 대신 다음 행동을 알려준다.
    #   종료코드는 전체 설치와 같은 '경고 후 계속' 철학으로 0을 유지한다.
    echo "⚠ 설치되지 않은 패키지가 있습니다:$DART_PACKAGES_MISSING"
    echo "   위 ⚠ 메시지와 네트워크 상태를 확인한 뒤 './linux-setup.sh --dart-only' 를 다시 실행해 주세요."
    echo "   (cob(co-bricks)은 GitHub 인증이 필요합니다 — 'gh auth login' 후 재시도)"
  fi
  exit 0
fi

# ============================================================
# 설치 단계 시작 (1~7.5단계) — --env-only 실행 시 이 블록 전체를 건너뛴다
#   (--system-only 는 9단계만, --dart-only 는 4-b단계만 위에서 실행하고 이미 종료했으므로
#    둘 다 여기까지 오지 않는다)
#   각 파트 본문을 옮기지 않고 그대로 감싸기만 했으므로, 블록 안쪽은 들여쓰기 없이 유지된다
#   (짝이 되는 fi는 8단계 직전에 있다)
# ============================================================
if (( ! ENV_ONLY )); then

# ============================================================
# 1. GUI 앱 + 1.6. Chrome 확장 프로그램 + 1.7. Pretendard 폰트
# ============================================================
#
# 이 세 단계는 "화면이 있는 데스크톱"에서만 의미가 있다.
# 서버·컨테이너처럼 화면이 없는 환경(HAS_GUI=1)에서는 수 GB짜리 앱을 내려받아도
# 실행할 방법이 없고 설치 시간만 길어지므로, 세 단계를 통째로 건너뛴다.
# ------------------------------------------------------------
if [[ "$HAS_GUI" -ne 0 ]]; then

  log "1 · 1.6 · 1.7. GUI 앱 · Chrome 확장 · Pretendard 폰트 (건너뜀)"
  warn "데스크톱 화면이 없는 환경으로 보입니다 → 1 · 1.6 · 1.7단계를 건너뜁니다"
  info "(서버·컨테이너·SSH 접속 환경에서는 GUI 앱이 실행되지 않습니다)"
  info "나중에 데스크톱 환경에서 이 스크립트를 다시 실행하면 그때 설치됩니다"

else

  # ------------------------------------------------------------
  # 1. GUI 앱 (apt 공식 저장소 · snap · 공식 설치 스크립트 · AppImage)
  #   맥은 Homebrew Cask 하나로 끝나지만 리눅스는 앱마다 배포 방식이 달라서
  #   저장소 등록(Chrome·1Password·Claude) / snap(Android Studio·Slack) /
  #   공식 스크립트(Tailscale·Zed) / AppImage(Orca·Lumide) 로 나뉜다.
  #   어떤 앱이 실패해도 나머지는 계속 깔린다.
  # ------------------------------------------------------------
  log "1. GUI 앱 설치 (Android Studio, Slack, Chrome, 1Password, Tailscale, Claude Desktop, Zed, Orca, Lumide) + 1Password CLI(op — 앱이 아닌 터미널 도구)"

  # snap 준비 — 우분투는 기본 탑재지만 데비안에는 없다. 없으면 먼저 깔아 둔다.
  #   (Android Studio·Slack이 snap으로만 공식 배포된다)
  if ! have snap; then
    info "snap이 없어 먼저 설치합니다 (Android Studio·Slack이 snap으로 배포됩니다)"
    apt_install snapd || warn "snapd 설치 실패 → snap 앱(Android Studio·Slack)은 건너뜁니다"
  fi

  # --- Android Studio (안드로이드 앱 개발 IDE) ---
  #   --classic: 스냅 샌드박스 밖의 파일·도구(안드로이드 SDK, 에뮬레이터 등)에 접근해야 해서 필요하다.
  snap_install android-studio --classic || true

  # --- Slack (팀 메신저) ---
  snap_install slack || true

  # --- Google Chrome (기본 브라우저 · 1.6단계의 ZenHub 확장도 여기에 붙는다) ---
  #   ⚠ 구글이 제공하는 리눅스 Chrome은 amd64(x86_64)뿐이다. ARM64 PC에서는 설치가
  #     실패하는데, 그 경우 우분투 기본 저장소의 chromium을 쓰면 확장·로그인 모두 동일하게 동작한다.
  if is_installed google-chrome-stable; then
    ok "Google Chrome 이미 설치됨"
  elif add_apt_repo google-chrome https://dl.google.com/linux/linux_signing_key.pub "https://dl.google.com/linux/chrome/deb/ stable main"; then
    apt_install google-chrome-stable || true
    if ! is_installed google-chrome-stable; then
      info "Chrome 설치에 실패했습니다 — ARM64 PC라면 대신 chromium을 쓰세요: sudo apt install chromium"
    fi
  else
    warn "Google Chrome 저장소 등록 실패 → 건너뜀"
    info "수동 설치: https://www.google.com/chrome/ 에서 .deb 내려받기"
  fi

  # --- 1Password 데스크톱 앱 + CLI(op) ---
  #   1Password CLI(op)는 앱이 아니라 터미널 도구다. 이 스크립트에서는 3.4단계(GitHub 인증)와
  #   8.5~8.9단계(팀 공용 토큰 주입)가 금고에서 값을 읽어오는 데 쓴다.
  #   ⚠ 1Password는 apt 저장소 등록만으로는 부족하고, 패키지 서명을 검증하는 debsig 정책 파일도
  #     함께 넣어 줘야 설치가 통과한다(공식 문서 절차). 정책 파일 작성이 실패해도 멈추지 않는다 —
  #     데스크톱 앱이 안 깔려도 CLI(op)만 깔리면 토큰 주입 단계는 정상 동작한다.
  if add_apt_repo 1password https://downloads.1password.com/linux/keys/1password.asc "https://downloads.1password.com/linux/debian/${ARCH} stable main"; then
    # debsig 정책 — 키 지문 AC2D62742012EA22 는 1Password 공식 문서에 명시된 값이다.
    OP_DEBSIG_POLICY="/etc/debsig/policies/AC2D62742012EA22"
    OP_DEBSIG_KEYRING="/usr/share/debsig/keyrings/AC2D62742012EA22"
    if [[ -f "$OP_DEBSIG_POLICY/1password.pol" && -f "$OP_DEBSIG_KEYRING/debsig.gpg" ]]; then
      ok "1Password 서명 검증(debsig) 설정 이미 완료됨"
    elif need_sudo; then
      if $SUDO install -d -m 0755 "$OP_DEBSIG_POLICY" "$OP_DEBSIG_KEYRING" \
        && curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol \
             | $SUDO tee "$OP_DEBSIG_POLICY/1password.pol" >/dev/null \
        && curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
             | gpg --dearmor 2>/dev/null | $SUDO tee "$OP_DEBSIG_KEYRING/debsig.gpg" >/dev/null; then
        ok "1Password 서명 검증(debsig) 설정 완료"
      else
        warn "1Password debsig 설정 실패 → 계속 진행 (데스크톱 앱 설치가 실패할 수 있습니다)"
      fi
    else
      warn "관리자 권한이 없어 1Password debsig 설정을 건너뜁니다"
    fi
    unset OP_DEBSIG_POLICY OP_DEBSIG_KEYRING

    apt_install 1password 1password-cli || true
    if ! have op && ! is_installed 1password-cli; then
      warn "1Password CLI(op) 설치 실패 → 3.4 · 8.5~8.9단계의 토큰 자동 주입을 건너뛰게 됩니다"
      info "수동 설치 안내: https://developer.1password.com/docs/cli/get-started/"
    fi
  else
    warn "1Password 저장소 등록 실패 → 데스크톱 앱·CLI 건너뜀"
    info "수동 설치 안내: https://support.1password.com/install-linux/"
  fi

  # --- Tailscale (팀 사설망 VPN) ---
  #   apt 저장소 이름이 배포판 코드명마다 달라서, 공식 설치 스크립트가 알아서 맞춰 주는 편이 안전하다.
  #   스크립트 내부에서 sudo를 쓰므로 관리자 권한이 없으면 안내만 하고 넘어간다.
  if have tailscale; then
    ok "Tailscale 이미 설치됨"
  elif need_sudo; then
    if curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1; then
      ok "Tailscale 설치 완료"
      info "설치 후 최초 1회 연결이 필요합니다: sudo tailscale up"
    else
      warn "Tailscale 설치 실패 → 건너뜀"
      info "수동 설치: curl -fsSL https://tailscale.com/install.sh | sh"
    fi
  else
    warn "관리자 권한이 없어 Tailscale 설치를 건너뜁니다"
    info "수동 설치: curl -fsSL https://tailscale.com/install.sh | sh"
  fi

  # --- Claude Desktop (Claude 데스크톱 앱) ---
  #   2026-06부터 공식 리눅스 베타가 apt 저장소로 배포된다. 베타라 저장소 주소가 바뀔 수 있으므로,
  #   실패하면 공식 다운로드 페이지만 안내하고 계속 진행한다.
  if is_installed claude-desktop; then
    ok "Claude Desktop 이미 설치됨"
  elif add_apt_repo claude-desktop https://downloads.claude.ai/claude-desktop/key.asc \
        "https://downloads.claude.ai/claude-desktop/apt/stable stable main"; then
    apt_install claude-desktop || true
    if ! is_installed claude-desktop; then
      info "저장소 주소가 바뀌었을 수 있습니다 → https://claude.com/download 에서 직접 내려받아 주세요"
    fi
  else
    warn "Claude Desktop 저장소 등록 실패 → 건너뜀 (리눅스 베타라 주소가 바뀌었을 수 있습니다)"
    info "직접 내려받기: https://claude.com/download"
  fi

  # --- Zed (코드 에디터) ---
  #   공식 설치 스크립트가 ~/.local/bin 아래에 깔아 준다(관리자 권한 불필요).
  #   같은 실행 세션의 뒷단계에서 바로 `zed`를 쓸 수 있도록 PATH에도 더해 둔다.
  if have zed || [[ -x "$HOME/.local/bin/zed" ]]; then
    ok "Zed 이미 설치됨"
  else
    if curl -fsSL https://zed.dev/install.sh | sh >/dev/null 2>&1; then
      ok "Zed 설치 완료 (~/.local/bin/zed)"
    else
      warn "Zed 설치 실패 → 건너뜀"
      info "수동 설치: curl -fsSL https://zed.dev/install.sh | sh"
    fi
  fi
  path_prepend "$HOME/.local/bin"

  # --- Orca (co:code 팀 개발 도구) ---
  #   리눅스판은 apt 저장소 없이 GitHub 릴리스에 AppImage 한 파일로 올라온다.
  #   ~/.local/bin/orca 로 받아 실행 권한을 주고, 앱 목록(런처)에서도 보이도록
  #   ~/.local/share/applications 에 바로가기(.desktop)를 만들어 둔다.
  ORCA_BIN="$HOME/.local/bin/orca"
  if [[ -x "$ORCA_BIN" ]] || have orca; then
    ok "Orca 이미 설치됨"
  else
    mkdir -p "$HOME/.local/bin" || true
    # 릴리스에 orca-linux.AppImage(x86_64) 와 orca-linux-arm64.AppImage 가 따로 올라온다.
    #   아키텍처를 무시하고 받으면 ARM64 PC 에서 "cannot execute binary file" 로 실행만 안 된다.
    if [[ "$ARCH" == "arm64" ]]; then ORCA_ASSET="orca-linux-arm64.AppImage"; else ORCA_ASSET="orca-linux.AppImage"; fi
    if curl -fsSL "https://github.com/stablyai/orca/releases/latest/download/$ORCA_ASSET" -o "$ORCA_BIN.part" \
      && chmod +x "$ORCA_BIN.part" \
      && mv "$ORCA_BIN.part" "$ORCA_BIN"; then
      ok "Orca 설치 완료 (~/.local/bin/orca)"
      mkdir -p "$HOME/.local/share/applications" || true
      cat > "$HOME/.local/share/applications/orca.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Orca
Comment=co:code 팀 개발 도구
Exec=$HOME/.local/bin/orca
Terminal=false
Categories=Development;
EOF
      ok "Orca 앱 바로가기 등록 완료 (앱 목록에서 'Orca'로 검색)"
      info "AppImage 실행에 FUSE가 필요합니다 — 실행이 안 되면: sudo apt install libfuse2"
    else
      rm -f "$ORCA_BIN.part"
      warn "Orca 내려받기 실패 → 건너뜀"
      info "직접 내려받기: https://github.com/stablyai/orca/releases/latest"
    fi
  fi
  unset ORCA_BIN

  # --- Lumide ---
  #   리눅스판은 AppImage 가 아니라 **tar.gz** 로 올라온다 (Lumide-Linux-<버전>-<아키텍처>.tar.gz).
  #   공개 레포라 gh 인증 없이 API 로 자산 주소를 찾을 수 있다. 자산 이름이 바뀌면 조용히
  #   공식 사이트만 안내하고 넘어간다.
  LUMIDE_REPO="SoFluffyOS/lumide"    # 릴리스 주소가 바뀌면 이 줄만 고치면 된다
  LUMIDE_BIN="$HOME/.local/bin/lumide"
  if have lumide || [[ -x "$LUMIDE_BIN" ]]; then
    ok "Lumide 이미 설치됨"
  else
    case "$ARCH" in
      arm64) LUMIDE_SUFFIX="arm64.tar.gz" ;;
      *)     LUMIDE_SUFFIX="x86_64.tar.gz" ;;
    esac
    # 임시 폴더를 못 만들면 아래 rm -rf가 엉뚱한 곳을 지우지 않도록 빈 값으로 두고 건너뛴다.
    LUMIDE_TMP="$(mktemp -d 2>/dev/null || true)"
    # 공개 레포라 인증 없이 릴리스 API 로 자산 주소를 얻는다.
    LUMIDE_URL="$(curl -fsSL "https://api.github.com/repos/$LUMIDE_REPO/releases/latest" 2>/dev/null \
      | grep '"browser_download_url"' | cut -d'"' -f4 | grep -- "$LUMIDE_SUFFIX" | head -1 || true)"
    if [[ -n "$LUMIDE_TMP" && -n "$LUMIDE_URL" ]] \
       && curl -fsSL "$LUMIDE_URL" -o "$LUMIDE_TMP/lumide.tar.gz" \
       && mkdir -p "$HOME/.local/share/lumide" \
       && tar -xzf "$LUMIDE_TMP/lumide.tar.gz" -C "$HOME/.local/share/lumide" --strip-components=1 2>/dev/null; then
      # 압축 안의 실행 파일 이름이 버전마다 다를 수 있어 실제로 찾아서 링크를 건다.
      LUMIDE_EXE="$(find "$HOME/.local/share/lumide" -maxdepth 2 -type f -name 'lumide*' -perm -u+x 2>/dev/null | head -1)"
      if [[ -n "$LUMIDE_EXE" ]]; then
        mkdir -p "$HOME/.local/bin" || true
        ln -sf "$LUMIDE_EXE" "$LUMIDE_BIN" && ok "Lumide 설치 완료 (~/.local/share/lumide)" \
          || warn "Lumide 바로가기 생성 실패 → 직접 실행: $LUMIDE_EXE"
      else
        warn "Lumide 압축을 풀었지만 실행 파일을 찾지 못했습니다 → 건너뜀"
        info "직접 내려받기: https://lumide.dev/"
      fi
      unset LUMIDE_EXE
    else
      warn "Lumide 릴리스 파일을 찾지 못했습니다 → 건너뜀 (자산 이름이 바뀌었을 수 있습니다)"
      info "직접 내려받기: https://lumide.dev/"
    fi
    unset LUMIDE_SUFFIX LUMIDE_URL
    if [[ -n "$LUMIDE_TMP" ]]; then rm -rf "$LUMIDE_TMP"; fi
    unset LUMIDE_TMP
  fi
  unset LUMIDE_REPO LUMIDE_BIN

  # 리눅스에는 Figma 데스크톱 앱이 없어 생략 — 대체: 웹(figma.com)으로 사용
  # 리눅스에는 Rive 데스크톱 앱이 없어 생략 — 대체: 웹(editor.rive.app)으로 사용
  # 리눅스에는 Dia 브라우저가 없어 생략 — 대체: 위에서 설치한 Chrome 사용

  # --- Stats 대체: btop (터미널 시스템 모니터) ---
  # 맥의 메뉴막대 모니터 Stats는 macOS 전용이라 생략 — 대체: btop
  #   터미널에서 `btop` 을 실행하면 CPU·메모리·디스크·네트워크 사용량을 한 화면에서 볼 수 있다.
  apt_install btop || warn "btop 설치 실패 → 건너뜀 (수동 설치: sudo apt install btop)"

  # 리눅스에는 Xcode가 없어 1.5단계(Xcode 설치·개발자 도구 전환)를 생략 — iOS 빌드는 맥에서만 가능
  # 같은 이유로 mas(App Store CLI)·CocoaPods도 생략한다 (안드로이드·웹 빌드는 리눅스에서 그대로 된다)

  # ------------------------------------------------------------
  # 1.6. Chrome 확장 프로그램 자동 추가 (ZenHub for GitHub)
  #   구글이 공식 문서화한 "External Extensions" 드롭인 방식을 쓴다:
  #   리눅스 Chrome은 /opt/google/chrome/extensions/<확장ID>.json 파일을 심어 두면
  #   다음 실행 시 스토어에서 자동으로 받아 설치한다(Preferences 파일을 직접 고치는 방식은
  #   브라우저의 변조 감지로 되돌아가므로 이 공식 경로만 동작한다).
  #   시스템 폴더라 관리자 권한이 필요하고, 권한이 없으면 방법만 안내하고 건너뛴다.
  # ------------------------------------------------------------
  log "1.6. Chrome 확장 프로그램 자동 추가 (ZenHub for GitHub)"

  ZENHUB_EXT_ID="ogcgkffhplmphkaahpmffcafajaocjbd"
  ZENHUB_EXT_DIR="/opt/google/chrome/extensions"
  ZENHUB_EXT_FILE="$ZENHUB_EXT_DIR/$ZENHUB_EXT_ID.json"
  if [[ ! -d /opt/google/chrome ]]; then
    warn "Chrome 미설치 → 확장 등록 건너뜀"
    info "Chrome을 설치한 뒤 이 스크립트를 다시 실행하면 자동으로 등록됩니다"
  elif [[ -f "$ZENHUB_EXT_FILE" ]]; then
    ok "Chrome: ZenHub for GitHub 확장 이미 등록됨"
  elif need_sudo; then
    if $SUDO install -d -m 0755 "$ZENHUB_EXT_DIR" \
      && echo '{"external_update_url": "https://clients2.google.com/service/update2/crx"}' | $SUDO tee "$ZENHUB_EXT_FILE" >/dev/null; then
      ok "Chrome: ZenHub for GitHub 확장 등록 완료 (다음 Chrome 실행 시 자동 설치됩니다)"
    else
      warn "Chrome: 확장 등록 실패 → 건너뜀"
      info "수동 설치: https://chromewebstore.google.com/detail/zenhub-for-github/$ZENHUB_EXT_ID"
    fi
  else
    warn "관리자 권한이 없어 확장 등록을 건너뜁니다"
    info "수동 설치: https://chromewebstore.google.com/detail/zenhub-for-github/$ZENHUB_EXT_ID"
  fi
  unset ZENHUB_EXT_ID ZENHUB_EXT_DIR ZENHUB_EXT_FILE

  # ------------------------------------------------------------
  # 1.7. Pretendard 폰트 설치 (9개 스타일)
  #   Figma 시안 등 디자인 작업에서 널리 쓰이는 한글 폰트 — 로컬에 없으면 시안과 다른 폰트로
  #   대체 렌더링되어 깨져 보인다. 맥은 brew cask 하나로 끝나지만 리눅스에는 공식 패키지가 없어
  #   공식 배포처(GitHub)에서 9개 굵기를 직접 내려받아 ~/.local/share/fonts 에 넣는다.
  #   (관리자 권한이 필요 없는 사용자 전용 폰트 폴더다)
  #   마지막에 fc-cache로 폰트 목록을 갱신해야 이미 실행 중인 앱 밖에서도 바로 인식된다.
  # ------------------------------------------------------------
  log "1.7. Pretendard 폰트 설치 (9개 스타일: Thin~Black)"

  PRETENDARD_DIR="$HOME/.local/share/fonts"
  PRETENDARD_BASE="https://github.com/orioncactus/pretendard/raw/main/packages/pretendard/dist/public/static"
  PRETENDARD_NEW=0
  mkdir -p "$PRETENDARD_DIR" || warn "폰트 폴더를 만들지 못했습니다 → 설치가 실패할 수 있습니다"
  for PRETENDARD_STYLE in Thin ExtraLight Light Regular Medium SemiBold Bold ExtraBold Black; do
    PRETENDARD_DST="$PRETENDARD_DIR/Pretendard-$PRETENDARD_STYLE.otf"
    if [[ -s "$PRETENDARD_DST" ]]; then
      ok "Pretendard $PRETENDARD_STYLE 이미 설치됨"
      continue
    fi
    # 받다가 끊긴 파일이 "설치됨"으로 남지 않도록 .part로 받아서 성공했을 때만 제자리로 옮긴다.
    if curl -fsSL "$PRETENDARD_BASE/Pretendard-$PRETENDARD_STYLE.otf" -o "$PRETENDARD_DST.part" \
      && mv "$PRETENDARD_DST.part" "$PRETENDARD_DST"; then
      ok "Pretendard $PRETENDARD_STYLE 설치 완료"
      PRETENDARD_NEW=1
    else
      rm -f "$PRETENDARD_DST.part"
      warn "Pretendard $PRETENDARD_STYLE 내려받기 실패 → 건너뜀"
    fi
  done

  if [[ "$PRETENDARD_NEW" -eq 1 ]]; then
    if have fc-cache; then
      fc-cache -f "$PRETENDARD_DIR" >/dev/null 2>&1 \
        && ok "폰트 목록 갱신 완료 (fc-cache)" \
        || warn "폰트 목록 갱신 실패 → 건너뜀 (수동: fc-cache -f)"
    else
      warn "fc-cache가 없어 폰트 목록을 갱신하지 못했습니다 (수동 설치: sudo apt install fontconfig)"
      info "폰트 파일은 이미 복사됐으므로 로그아웃 후 다시 로그인하면 인식됩니다"
    fi
  fi
  unset PRETENDARD_DIR PRETENDARD_BASE PRETENDARD_NEW PRETENDARD_STYLE PRETENDARD_DST

fi

# ------------------------------------------------------------
# 1.8. 1Password CLI(op) — 화면 없는 환경 보완
#   op 는 앱이 아니라 **터미널 도구**다. 위 1단계(GUI 전용 블록) 안에서 데스크톱 앱과 함께
#   깔리지만, 화면 없는 서버·컨테이너에서는 그 블록을 통째로 건너뛰므로 op 도 함께 빠진다.
#   그러면 3.4단계(GitHub 자동 로그인)와 8.5~8.9단계(팀 토큰 주입)가 전부 무력화된다.
#   → 데스크톱이든 아니든 op 만큼은 반드시 확보한다. (이미 있으면 그대로 넘어간다)
# ------------------------------------------------------------
if have op; then
  :   # 1단계에서 이미 설치됨 — 조용히 넘어간다
else
  log "1.8. 1Password CLI(op) 설치 (팀 토큰 자동 주입에 필요)"
  if add_apt_repo 1password https://downloads.1password.com/linux/keys/1password.asc \
      "https://downloads.1password.com/linux/debian/${ARCH} stable main"; then
    apt_install 1password-cli || true
  fi
  if have op; then
    ok "op 설치 완료"
  else
    warn "1Password CLI(op) 설치 실패 → 3.4 · 8.5~8.9단계의 토큰 자동 주입을 건너뛰게 됩니다"
    info "수동 설치 안내: https://developer.1password.com/docs/cli/get-started/"
  fi
fi

# ============================================================
# 2 / 2.5 / 2.6 / 2.7 — AI 코딩 CLI (Claude Code · MCP · codex·agy · Slack CLI)
# ============================================================

# ------------------------------------------------------------
# 2. Claude Code CLI
#   공식 설치 스크립트(https://claude.ai/install.sh)로 설치한다 — apt·snap 패키지 대신
#   공식 홈페이지 권장 방식(자동 업데이트 내장, 관리자 권한 불필요). 바이너리가
#   ~/.local/bin/claude 에 설치되므로, 같은 실행 세션의 뒷단계(2.5 MCP 등록)와
#   멱등 체크가 바로 동작하도록 PATH에 먼저 반영한다.
#   (~/.local/bin 을 ~/.zshrc PATH에 넣는 일은 8단계가 따로 한다)
# ------------------------------------------------------------
log "2. Claude Code CLI 설치 (공식 설치 스크립트)"
path_prepend "$HOME/.local/bin"
if have claude; then
  ok "claude 이미 설치됨"
else
  curl -fsSL https://claude.ai/install.sh | bash || true
  # 설치 직후에야 ~/.local/bin 폴더가 생기는 경우가 있어 한 번 더 잡아 준다
  # (path_prepend 는 폴더가 없으면 아무것도 하지 않고, 중복 추가도 하지 않는다)
  path_prepend "$HOME/.local/bin"
  # 성공 판정은 인스톨러 종료 코드가 아니라 바이너리 존재로 확인한다
  # (curl 실패 시 bash가 빈 입력으로 0 종료하는 false-success, 인스톨러가
  #  설치 후 부수 단계에서 비0 종료하는 false-failure 모두 방지)
  if have claude; then
    ok "claude 설치 완료 (~/.local/bin/claude)"
  else
    warn "claude 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://claude.ai/install.sh | bash)"
  fi
fi

# ------------------------------------------------------------
# 2.5. Claude Code MCP 서버 / 플러그인 (jira=atlassian, figma, zenhub, slack)
#   MCP는 3계층으로 설치된다:
#     ① 플러그인 계층  : claude plugin install (figma) — 아래에서 자동
#     ② 로컬 바이너리   : marionette_mcp·dart mcp-server(4단계에서 설치)
#     ③ 인증 계층      : figma OAuth는 최초 1회 `/mcp`에서 수동 로그인 (자동화 불가),
#                        zenhub·jira·slack은 ~/.zshrc의 팀 공용 토큰(런타임 확장)으로 인증 — 토큰 값은 커밋 금지
#   ※ jira(atlassian)는 과거 OAuth 플러그인이었으나, 매번 `/mcp` 로그인하는 수고를 없애려고 팀 공용
#     토큰 방식으로 전환했다. 공식 원격 MCP(mcp.atlassian.com, Rovo)는 조직 Rovo 엔타이틀먼트로 막혀,
#     Jira REST API에 토큰으로 직접 붙는 오픈소스 MCP(sooperset/mcp-atlassian, Docker)로 붙인다.
#     → 개발팀 공용 계정(dev@cocode.im)의 Jira 토큰만 있으면 되고 Rovo 권한이 필요 없다. (토큰 주입은 8.6단계)
#     ⚠ 런타임에 docker 데몬이 떠 있어야 이 MCP가 뜬다(팀은 backend 개발로 docker 상시 사용).
#       맥은 colima를 쓰지만 리눅스는 docker 데몬이 systemd 서비스로 직접 돈다 — docker 설치는 3단계,
#       내 계정을 docker 그룹에 넣는 일은 9단계가 맡는다.
#   ※ 여기서 하는 일은 "등록(설정 파일에 정의를 적는 것)"뿐이라, 실행에 필요한 docker·npx가
#     아직 없어도 등록 자체는 문제없이 끝난다. npx는 6단계(Node), docker는 3단계에서 깔린다.
#   ※ marionette·dart·figma(serve) MCP 정의는 사설 cocode-skills 플러그인 번들에서 제공됨
#     (coco-de/skills의 install.sh — 아래 3.5단계에서 설치)
# ------------------------------------------------------------
log "2.5. Claude Code MCP 설치 (figma 플러그인 + zenhub·jira·slack 토큰 등록)"

if have claude; then
  # 공식 마켓플레이스 등록 (이미 있으면 무시)
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 || true

  # 원격 OAuth 플러그인(figma): 설치는 자동, 로그인은 최초 1회 `/mcp`에서 수동
  #   ※ atlassian은 더 이상 OAuth 플러그인으로 설치하지 않는다(아래 토큰 방식으로 대체).
  for p in figma; do
    if claude plugin list 2>/dev/null | grep -q "${p}@claude-plugins-official"; then
      ok "${p} 플러그인 이미 설치됨"
    else
      claude plugin install "${p}@claude-plugins-official" --scope user >/dev/null 2>&1 \
        && ok "${p} 플러그인 설치 (최초 1회 /mcp 로그인 필요)" \
        || warn "${p} 플러그인 설치 실패 → 건너뜀 (claude 로그인 후 재시도)"
    fi
  done

  # atlassian(jira): 예전엔 OAuth 플러그인이었으나 토큰 방식으로 전환 →
  #   기존에 설치된 atlassian OAuth 플러그인이 있으면 제거해야 아래 토큰 등록이 'atlassian' 이름을 차지한다.
  if claude plugin list 2>/dev/null | grep -q "atlassian@claude-plugins-official"; then
    claude plugin uninstall atlassian@claude-plugins-official >/dev/null 2>&1 \
      && echo "  · 기존 atlassian OAuth 플러그인 제거 (토큰 방식으로 전환)" \
      || warn "기존 atlassian OAuth 플러그인 제거 실패 → 수동 제거 필요(claude plugin uninstall atlassian@claude-plugins-official)"
  fi

  # zenhub MCP (사설 cocode-skills 루트 .mcp.json과 동일 구조 — 원격 서버 + API 토큰)
  #   토큰은 ~/.zshrc의 ZENHUB_API_TOKEN에서 런타임 확장되므로 단일따옴표로 리터럴 등록 (토큰 값 커밋 금지)
  #   ⚠ '이미 있으면 건너뛰기'가 아니라 항상 remove 후 add 한다 — 그래야 정의가 바뀐 업데이트(헤더/워크스페이스
  #     등)를 재실행만으로 반영한다. remove는 등록이 없을 때 실패해도 무해(|| true).
  claude mcp remove zenhub >/dev/null 2>&1 || true
  claude mcp add zenhub --scope user -- \
    npx -y mcp-remote https://api.zenhub.com/mcp \
    --header 'Authorization:${ZENHUB_API_TOKEN}' \
    --header 'X-zh-workspace:69ae742925c359000f5acf14' >/dev/null 2>&1 \
    && ok "zenhub MCP 등록/갱신 (토큰은 8.5단계에서 1Password 공용 항목으로 주입)" \
    || warn "zenhub MCP 등록 실패 → 건너뜀"

  # 기존 Rovo 방식 atlassian MCP가 남아 있으면 제거(엔타이틀먼트로 막혀 미동작) → 아래 mcp-atlassian으로 대체.
  #   grep 없이 무조건 remove — 없을 때 실패해도 무해(|| true).
  claude mcp remove atlassian >/dev/null 2>&1 && echo "  · 기존 Rovo atlassian MCP 제거 (REST 직결 방식으로 전환)" || true

  # jira MCP = sooperset/mcp-atlassian (Docker) — Jira Cloud REST API에 토큰으로 직접 붙는다(Rovo 우회).
  #   인증: JIRA_URL/JIRA_USERNAME/JIRA_API_TOKEN 환경변수 → 서버가 내부적으로 Basic(email:token) 처리.
  #   토큰만 비밀이라 --env 'JIRA_API_TOKEN=${JIRA_API_TOKEN}'로 리터럴 등록(claude가 런타임에 ~/.zshrc 값으로 확장,
  #   config에는 '${JIRA_API_TOKEN}' 문자열만 저장 — 값 커밋/노출 없음). URL·이메일은 비밀 아님(직접 기입).
  #   먼저 이미지 pull(없으면 최초 claude 실행 때 pull되며 지연). docker 명령과 데몬이 모두 필요하다.
  #   ⚠ 이 단계(2.5)는 docker를 까는 3단계보다 먼저라, 첫 설치 때는 docker가 아직 없는 게 정상이다 —
  #     그럴 땐 이미지 준비만 건너뛰고 등록은 그대로 진행한다(등록은 설정 파일에 적는 일이라 docker가 필요 없다).
  #   ⚠ zenhub와 동일하게 항상 remove 후 add — 정의가 바뀐 업데이트(이미지 태그·env·args 변경)를 재실행만으로 반영.
  if have docker && docker info >/dev/null 2>&1; then
    docker pull ghcr.io/sooperset/mcp-atlassian:latest >/dev/null 2>&1 \
      && echo "  · mcp-atlassian 도커 이미지 준비됨" \
      || warn "mcp-atlassian 이미지 pull 실패 → 최초 사용 시 자동 pull(지연) 또는 수동 확인"
  elif have docker; then
    warn "docker 데몬이 꺼져 있어 이미지 준비를 건너뜁니다 (등록은 계속)"
    info "sudo systemctl start docker 로 켠 뒤, 로그아웃/로그인해 docker 그룹이 반영됐는지도 확인해 주세요(9단계)"
  else
    warn "docker 가 아직 없어 mcp-atlassian 이미지 준비를 건너뜁니다 (등록은 계속)"
    info "docker는 3단계에서 설치됩니다 — 설치가 끝난 뒤 ./linux-setup.sh 를 한 번 더 돌리면 이미지까지 준비됩니다"
  fi
  claude mcp remove mcp-atlassian >/dev/null 2>&1 || true
  claude mcp add mcp-atlassian --scope user \
    --env JIRA_URL=https://laputa.atlassian.net \
    --env JIRA_USERNAME=dev@cocode.im \
    --env 'JIRA_API_TOKEN=${JIRA_API_TOKEN}' \
    -- docker run --rm -i -e JIRA_URL -e JIRA_USERNAME -e JIRA_API_TOKEN \
       ghcr.io/sooperset/mcp-atlassian:latest --transport stdio >/dev/null 2>&1 \
    && ok "mcp-atlassian(jira) MCP 등록/갱신 (토큰은 8.6단계에서 1Password 공용 항목으로 주입)" \
    || warn "mcp-atlassian 등록 실패 → 건너뜀"

  # slack MCP = @modelcontextprotocol/server-slack (Anthropic 공식 레퍼런스 서버, npx 실행).
  #   SLACK_BOT_TOKEN·SLACK_TEAM_ID는 ~/.zshrc에서 런타임 확장되므로 zenhub·jira와 동일하게
  #   단일따옴표 '${VAR}' 리터럴로 등록(토큰 값 커밋 금지). 값 자체는 8.9단계에서 1Password
  #   팀 공용 항목("Cocode Slack")으로 주입된다.
  #   ⚠ zenhub·jira와 동일하게 항상 remove 후 add — 정의가 바뀐 업데이트를 재실행만으로 반영.
  claude mcp remove slack >/dev/null 2>&1 || true
  claude mcp add slack --scope user \
    --env 'SLACK_TEAM_ID=${SLACK_TEAM_ID}' \
    --env 'SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}' \
    -- npx -y @modelcontextprotocol/server-slack >/dev/null 2>&1 \
    && ok "slack MCP 등록/갱신 (토큰은 8.9단계에서 1Password 공용 항목으로 주입)" \
    || warn "slack MCP 등록 실패 → 건너뜀"
else
  warn "claude CLI가 없어 MCP 플러그인 설치를 건너뜁니다"
fi

# maestro CLI: 팀 표준 세팅에서 제외됨 → 더 이상 설치하지 않는다.
#   ※ pixel-loop 플러그인에 딸린 maestro MCP는 이 CLI가 있어야 뜨므로, 앞으로는 연결되지 않는다.
#     maestro가 꼭 필요한 사람은 직접 설치하면 된다(curl -Ls https://get.maestro.mobile.dev | bash).
#   예전 버전 스크립트로 세팅한 PC에는 아직 남아 있을 수 있는데, 공식 제거 수단이 없어
#   스크립트가 임의 경로를 지우지 않는다 — 위치만 알려주고 삭제는 본인 판단에 맡긴다.
if have maestro; then
  echo "  · maestro CLI가 아직 남아 있습니다 — 팀 표준에서 빠졌으니 필요 없으면 직접 지워 주세요:"
  echo "      rm -rf \"\$HOME/.maestro\"   (그리고 ~/.zshrc의 .maestro/bin PATH 줄 삭제)"
fi
# marionette_mcp / dart mcp-server 는 4단계(Dart 글로벌 패키지 / FVM)에서 설치됨

# flutter-mcp-toolkit (mcp_flutter): 팀 표준 세팅에서 제외됨 → 더 이상 설치하지 않는다.
#   예전 버전 스크립트로 세팅한 PC에는 아직 남아 있을 수 있어, 재실행하면 아래에서 정리된다.
#     · Claude 플러그인 / 마켓플레이스: 자동 제거 (없으면 조용히 건너뜀 — 멱등)
#     · CLI 바이너리: 공식 제거 수단이 없어 스크립트가 임의 경로를 지우지 않는다. 위치만 알려주고 삭제는 본인 판단에 맡긴다
#   ※ 실행 중인 Flutter 앱 조작은 marionette·dart MCP(4단계 설치)로 계속 가능하다
if have claude; then
  # 플러그인 id는 마켓플레이스 이름에 따라 달라져(예: @flutter-mcp-toolkit / @Arenukvern-mcp_flutter)
  # 고정 문자열로 찾지 않고 실제 목록에서 뽑아 쓴다.
  FMT_PLUGIN=$(claude plugin list 2>/dev/null | grep -o 'flutter-mcp-toolkit@[^ ]*' | head -1)
  if [[ -n "$FMT_PLUGIN" ]]; then
    claude plugin uninstall "$FMT_PLUGIN" >/dev/null 2>&1 \
      && echo "  · 기존 flutter-mcp-toolkit 플러그인 제거 (팀 표준 세팅에서 제외됨)" \
      || warn "flutter-mcp-toolkit 플러그인 제거 실패 → 수동 제거 필요(claude plugin uninstall $FMT_PLUGIN)"
  fi
  # 플러그인을 지워도 마켓플레이스 등록은 남으므로 함께 정리한다 (이 마켓플레이스는 이 도구 전용).
  FMT_MARKET=$(claude plugin marketplace list 2>/dev/null | grep -B1 'Arenukvern/mcp_flutter' | sed -n 's/.*❯ *//p' | head -1)
  if [[ -n "$FMT_MARKET" ]]; then
    claude plugin marketplace remove "$FMT_MARKET" >/dev/null 2>&1 \
      && echo "  · 기존 flutter-mcp-toolkit 마켓플레이스 등록 해제" \
      || warn "flutter-mcp-toolkit 마켓플레이스 해제 실패 → 수동 제거 필요(claude plugin marketplace remove $FMT_MARKET)"
  fi
fi
if have flutter-mcp-toolkit; then
  echo "  · flutter-mcp-toolkit CLI가 아직 남아 있습니다 — 팀 표준에서 빠졌으니 필요 없으면 직접 지워 주세요:"
  echo "      rm -f \"$(command -v flutter-mcp-toolkit)\""
fi

# ------------------------------------------------------------
# 2.6. 다른 AI 코딩 CLI (codex, antigravity(agy))
#   Claude Code와 나란히 터미널에서 쓰는 AI 코딩 에이전트 두 가지를 추가로 설치한다.
#     · codex (OpenAI): 리눅스에는 맥의 Homebrew cask가 없어 npm 전역 설치가 공식 표준이다
#             (npm install -g @openai/codex). 바이너리는 `codex`. 최초 실행 시 ChatGPT 계정 로그인.
#             ⚠ 이 단계는 Node를 까는 6단계보다 앞이라 첫 설치 때는 npm이 없는 게 정상이다 —
#               그럴 땐 방법만 안내하고 건너뛴다(6단계 이후 재실행하면 설치된다).
#     · agy   (Google Antigravity CLI): 은퇴한 Gemini CLI의 공식 후속 도구. 단일 Go 바이너리라
#             Claude Code와 똑같이 공식 설치 스크립트로 ~/.local/bin/agy 에 설치한다(node·python 불필요).
#             최초 실행 시 Google 계정으로 로그인.
#   두 도구 모두 멱등(이미 있으면 건너뜀) · 실패 시 ⚠ 후 계속.
# ------------------------------------------------------------
log "2.6. 다른 AI 코딩 CLI 설치 (codex, antigravity(agy))"

# codex (OpenAI) — npm 전역 설치
if have codex; then
  ok "codex 이미 설치됨"
elif have npm; then
  # sudo 없이 깔리도록 npm 전역 경로는 nvm(6단계)이 잡아 준 사용자 폴더를 쓴다.
  # 시스템 node(/usr/bin/node)에서는 권한 문제로 실패할 수 있어, 실패해도 경고만 하고 넘어간다.
  npm install -g @openai/codex >/dev/null 2>&1 \
    && ok "codex 설치 완료 (최초 실행 시 codex 로 ChatGPT 로그인)" \
    || warn "codex 설치 실패 → 건너뜀 (수동 설치: npm install -g @openai/codex)"
else
  warn "npm 이 아직 없어 codex 설치를 건너뜁니다"
  info "6단계(Node.js) 설치가 끝난 뒤 새 터미널에서 'npm install -g @openai/codex' 를 실행하거나,"
  info "./linux-setup.sh 를 한 번 더 돌리면 자동으로 설치됩니다"
fi

# agy (Google Antigravity CLI) — 공식 설치 스크립트 (Claude Code와 동일 패턴, ~/.local/bin)
#   같은 실행 세션의 아래 단계·검증에서 바로 잡히도록 PATH를 먼저 반영한다(2단계와 동일).
path_prepend "$HOME/.local/bin"
if have agy; then
  ok "agy(antigravity) 이미 설치됨"
else
  curl -fsSL https://antigravity.google/cli/install.sh | bash || true
  path_prepend "$HOME/.local/bin"
  # 성공 판정은 인스톨러 종료 코드가 아니라 바이너리 존재로 확인한다 (Claude Code와 동일 이유)
  if have agy; then
    ok "agy(antigravity) 설치 완료 (~/.local/bin/agy, 최초 실행 시 agy 로 Google 로그인)"
  else
    warn "agy 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://antigravity.google/cli/install.sh | bash)"
    info "리눅스판이 아직 제공되지 않을 수 있습니다 — 없어도 나머지 설치에는 지장이 없습니다"
  fi
fi

# ------------------------------------------------------------
# 2.7. Slack CLI (slack)
#   Slack 앱/워크플로 개발용 공식 CLI(slackapi/slack-cli). 공식 설치 스크립트가
#   바이너리를 ~/.slack에 내려받고 심볼릭 링크를 걸어 준다 — 리눅스에서는 링크 위치가
#   /usr/local/bin(관리자 권한 필요)으로 잡힐 수 있어, 관리자 암호를 묻지 않도록
#   ~/.local/bin 에 직접 링크를 만들어 마무리한다.
#   claude/agy와 동일하게 성공 판정은 종료 코드가 아니라 바이너리 존재(have slack)로 확인한다.
#   ~/.local/bin 은 2단계에서 이미 PATH에 반영됨.
# ------------------------------------------------------------
log "2.7. Slack CLI 설치 (공식 설치 스크립트)"
# ⚠ 1단계에서 깐 Slack **데스크톱 앱**(snap)이 /snap/bin/slack 을 만든다. `have slack` 만 보면
#   그 앱을 CLI 로 착각해 "이미 설치됨"으로 넘어가고, Slack CLI 는 영영 깔리지 않는다.
#   그래서 이름이 아니라 **동작**으로 판별한다 — CLI 만 `slack version` 에 응답한다.
have_slack_cli() {
  have slack || return 1
  slack version </dev/null >/dev/null 2>&1
}
if have_slack_cli; then
  ok "slack(CLI) 이미 설치됨"
else
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash || true
  path_prepend "$HOME/.local/bin"
  # 인스톨러가 링크를 걸지 못했으면(관리자 권한 없음) ~/.slack 안의 실제 바이너리를 직접 이어 준다.
  if ! have_slack_cli && [[ -x "$HOME/.slack/bin/slack" ]]; then
    ln -sf "$HOME/.slack/bin/slack" "$HOME/.local/bin/slack" 2>/dev/null || true
    path_prepend "$HOME/.local/bin"
  fi
  if have_slack_cli; then
    ok "slack(CLI) 설치 완료 (최초 사용 시 slack login 으로 워크스페이스 인증)"
  else
    warn "slack 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash)"
  fi
fi

# ============================================================
# 3. CLI 도구 · 3.2 Git 이메일 · 3.3 브라우저 번역 · 3.4 GitHub 인증 · 3.5 cocode-skills
# ============================================================

# ------------------------------------------------------------
# 3. CLI 도구 (go, git, gh, jq, docker, direnv, openjdk-17, lefthook 등)
#   맥(brew)에서 한 줄로 깔던 도구들을, 리눅스에서는 성격에 따라 세 가지 방법으로 나눠 깐다.
#     1) 배포판 apt 저장소   — 버전이 충분히 최신인 기본 도구들
#     2) 공식 apt 저장소     — gh·docker 처럼 배포판 판이 낡아 공식 저장소가 필요한 도구
#     3) 공식 설치 스크립트  — awscli·lefthook 처럼 apt 에 아예 없는 도구
# ------------------------------------------------------------
log "3. CLI 도구 설치 (go, git, gh, jq, docker, direnv, openjdk-17, lefthook 등)"

# zsh-syntax-highlighting · direnv · openjdk-17: 팀 .zshrc 가 참조하는 도구들.
# unzip: 아래 awscli 공식 설치본(zip)과 Android SDK 압축 해제에 쓴다.
# golang-go: 맥의 `brew install go` 에 해당한다 (명령 이름은 똑같이 `go`).
apt_install golang-go git jq zsh-syntax-highlighting direnv openjdk-17-jdk unzip \
  || warn "일부 CLI 도구 설치 실패 → 건너뜀 (수동 설치: sudo apt install golang-go git jq direnv openjdk-17-jdk)"

# 리눅스에는 CocoaPods·fastlane 을 깔지 않는다 — iOS 빌드는 리눅스에서 불가 — 생략
#   (iOS 관련 작업은 맥에서 co-mac 으로 세팅한 장비를 쓴다)

# pyenv·nvm 은 여기서 깔지 않는다 — 5단계(Python)·6단계(Node.js)가 각각 공식 설치
#   스크립트로 홈 폴더에 직접 설치한다. apt 판 pyenv 는 아예 없고, apt 판 nodejs 는
#   버전 전환이 안 돼 팀 표준(nvm)과 어긋난다.

# gh(GitHub CLI) — 우분투 기본 저장소 판은 버전이 뒤처져 3.4단계의 `gh auth login --with-token`,
#   3.5단계의 `gh api` 동작이 달라질 수 있어 GitHub 공식 저장소를 등록해 설치한다.
if have gh; then
  ok "gh 이미 설치됨"
else
  add_apt_repo github-cli \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    "https://cli.github.com/packages stable main" \
    || warn "GitHub CLI 저장소 등록 실패 → gh 설치를 건너뜁니다 (수동 설치: https://github.com/cli/cli/blob/trunk/docs/install_linux.md)"
  apt_install gh || warn "gh 설치 실패 → 건너뜀 (3.4·3.5단계의 GitHub 인증·팀 플러그인 설치도 함께 건너뜁니다)"
fi

# docker — 도커 공식 저장소에서 설치한다.
#   배포판 기본 저장소의 docker.io 는 버전이 한참 뒤처져 buildx·compose v2 가 빠져 있다.
#   맥·윈도우 팀원과 같은 명령(`docker compose ...`)을 쓰려면 공식 저장소가 필요하다.
#
#   ⚠ colima 는 설치하지 않는다 — colima 는 맥에서 도커 데몬을 돌릴 리눅스 VM 을 띄우려고
#     쓰던 도구다. 리눅스는 도커가 네이티브로 돌아가므로 VM 자체가 필요 없다.
#   ⚠ docker-compose(구 v1) 도 따로 깔지 않는다 — 공식 저장소의 docker-compose-plugin 이
#     `docker compose` 명령으로 같은 일을 한다.
#   ⚠ sudo 없이 docker 를 쓰려면 docker 그룹에 들어가야 하는데, 그 작업은 9단계(시스템 권한)가
#     맡는다. 여기서는 설치까지만 한다.
if have docker; then
  ok "docker 이미 설치됨"
else
  # 도커는 우분투용/데비안용 저장소를 따로 운영한다. 민트·Pop!_OS 같은 우분투 파생 배포판은
  # 우분투용 저장소를 그대로 쓰면 된다(DISTRO_CODENAME 도 헤더에서 우분투 코드명으로 잡아 둔다).
  if [[ "$DISTRO_ID" == "debian" ]]; then
    docker_distro="debian"
  else
    docker_distro="ubuntu"
  fi
  add_apt_repo docker \
    "https://download.docker.com/linux/${docker_distro}/gpg" \
    "https://download.docker.com/linux/${docker_distro} ${DISTRO_CODENAME} stable" \
    || warn "도커 저장소 등록 실패 → docker 설치를 건너뜁니다 (수동 설치: https://docs.docker.com/engine/install/)"
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    || warn "docker 설치 실패 → 건너뜀 (수동 설치: https://docs.docker.com/engine/install/)"
  unset docker_distro
fi

# awscli — apt 판(awscli)은 구버전(v1)이라 팀에서 쓰는 v2 명령과 옵션이 다르다.
#   AWS 공식 zip(v2) 을 받아 설치하고, 실패하면 그마저도 없는 것보다는 나으니 apt 판으로 대체한다.
if have aws; then
  ok "awscli 이미 설치됨"
elif ! need_sudo; then
  warn "관리자 권한이 없어 awscli 설치를 건너뜁니다 (수동 설치: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
else
  aws_tmp="$(mktemp -d)"
  if have unzip \
     && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$aws_tmp/awscliv2.zip" \
     && unzip -q "$aws_tmp/awscliv2.zip" -d "$aws_tmp" \
     && $SUDO "$aws_tmp/aws/install" --update >/dev/null 2>&1; then
    ok "awscli 설치 완료 (AWS 공식 v2 설치본)"
  else
    warn "awscli 공식 설치본(zip) 설치 실패 → apt 판(v1)으로 대체 시도"
    apt_install awscli || warn "awscli 설치 실패 → 건너뜀 (수동 설치: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"
  fi
  rm -rf "$aws_tmp"
  unset aws_tmp
fi

# lefthook — 커밋·푸시 직전에 포맷/린트/테스트를 자동으로 돌려주는 Git 훅 관리자.
#   팀 레포에 lefthook.yml 이 있으면 이 CLI 가 깔려 있어야 훅이 동작한다
#   (레포별로 최초 1회 `lefthook install` 필요 — 완료 안내 10단계 참고).
#   배포판 apt 저장소에는 없어서 공식 설치 스크립트를 쓰고, 그것도 실패하면 go 로 직접 빌드한다.
if have lefthook; then
  ok "lefthook 이미 설치됨"
else
  # ⚠ 예전 안내에 있던 raw.githubusercontent.com/.../install.sh 는 **지금 404 다**(레포에서 삭제됨).
  #   대신 GitHub 릴리스에 올라오는 정적 바이너리(lefthook_<버전>_Linux_<아키텍처>.gz)를 직접 받는다.
  #   공개 레포라 인증이 필요 없다.
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  case "$ARCH" in
    arm64) lh_arch="arm64" ;;
    *)     lh_arch="x86_64" ;;
  esac
  lh_tag="$(curl -fsSL https://api.github.com/repos/evilmartians/lefthook/releases/latest 2>/dev/null \
            | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
  if [[ -n "$lh_tag" ]]; then
    lh_tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/evilmartians/lefthook/releases/download/${lh_tag}/lefthook_${lh_tag#v}_Linux_${lh_arch}.gz" -o "$lh_tmp/lefthook.gz" \
       && gunzip -c "$lh_tmp/lefthook.gz" > "$HOME/.local/bin/lefthook" 2>/dev/null \
       && chmod +x "$HOME/.local/bin/lefthook"; then
      path_prepend "$HOME/.local/bin"
    else
      rm -f "$HOME/.local/bin/lefthook"
    fi
    rm -rf "$lh_tmp"
  fi
  unset lh_arch lh_tag lh_tmp
  hash -r 2>/dev/null || true
  if ! have lefthook && have go; then
    # go 폴백 — 방금 3단계에서 golang-go 를 깔았으므로 대개 여기서 성공한다.
    info "공식 설치 스크립트가 실패해 go 로 직접 설치를 시도합니다 (조금 걸릴 수 있습니다)"
    GOBIN="$HOME/go/bin" go install github.com/evilmartians/lefthook@latest >/dev/null 2>&1 || true
    path_prepend "$HOME/go/bin"
    hash -r 2>/dev/null || true
  fi
  if have lefthook; then
    ok "lefthook 설치 완료"
  else
    warn "lefthook 설치 실패 → 건너뜀"
    info "수동 설치: https://github.com/evilmartians/lefthook/releases 에서 lefthook_<버전>_Linux_<아키텍처>.gz 를 받아"
    info "           gunzip 후 ~/.local/bin/lefthook 으로 옮기고 chmod +x 하세요"
  fi
fi

# ------------------------------------------------------------
# 3.2. Git 전역 사용자 이메일 설정 (커밋 작성자 정보)
#   커밋에 기록될 회사 이메일을 입력받아 git config --global user.email 에 저장한다.
#   이미 설정돼 있으면 그대로 두고 건너뜀(멱등).
#   파이프 실행(TTY 없음)이면 멈추지 않고 건너뜀(재실행 시 입력 가능).
# ------------------------------------------------------------
log "3.2. Git 사용자 이메일 설정 (git config --global user.email)"
if ! have git; then
  warn "git 이 없어 이메일 설정을 건너뜁니다 (위 3단계 확인 후 재실행)"
else
  GIT_EMAIL_CURRENT="$(git config --global user.email 2>/dev/null || true)"
  if [[ -n "$GIT_EMAIL_CURRENT" ]]; then
    ok "이미 설정됨 ($GIT_EMAIL_CURRENT)"
  elif [[ -t 0 ]]; then
    while true; do
      printf "  ✉️  커밋에 사용할 회사 이메일을 입력하세요 (예: cody@cocode.im) · 건너뛰려면 s 입력 후 Enter: "
      read -r git_email || git_email="s"
      if [[ "$git_email" == "s" || "$git_email" == "S" ]]; then
        warn "Git 이메일 설정 건너뜀 → 나중에 직접 실행: git config --global user.email <이메일>"
        break
      fi
      if [[ "$git_email" == *@* ]]; then
        # || 로 받지 않으면 (예: ~/.gitconfig 가 읽기 전용) set -e 에 걸려 여기서 스크립트가 죽는다.
        git config --global user.email "$git_email" \
          && ok "user.email 설정 완료 ($git_email)" \
          || warn "user.email 설정 실패 → 건너뜀 (수동: git config --global user.email $git_email)"
        break
      fi
      echo "  ✗ 이메일 형식이 아닙니다(@가 없음) — 다시 입력해 주세요."
    done
    unset git_email
  else
    warn "비대화형 실행 → Git 이메일 설정 건너뜀. 직접 실행: git config --global user.email <이메일>"
  fi
  unset GIT_EMAIL_CURRENT

  # 줄바꿈 문자 처리 — 맥·윈도우 팀원과 같은 파일을 주고받아도 줄바꿈이 어긋나지 않게 한다.
  #   input = "받을 때는 건드리지 않고, 커밋할 때만 CRLF 를 LF 로 바꾼다" 는 뜻으로,
  #   맥(co-mac)·리눅스의 기본값이자 윈도우(co-win)와 충돌하지 않는 설정이다.
  #   이미 값이 있으면 팀원이 일부러 바꿔 둔 것일 수 있으니 건드리지 않는다(멱등).
  GIT_AUTOCRLF_CURRENT="$(git config --global core.autocrlf 2>/dev/null || true)"
  if [[ -n "$GIT_AUTOCRLF_CURRENT" ]]; then
    ok "core.autocrlf 이미 설정됨 ($GIT_AUTOCRLF_CURRENT)"
  else
    git config --global core.autocrlf input \
      && ok "core.autocrlf=input 설정 완료 (맥·윈도우 팀원과 줄바꿈이 어긋나지 않게)" \
      || warn "core.autocrlf 설정 실패 → 건너뜀 (수동: git config --global core.autocrlf input)"
  fi
  unset GIT_AUTOCRLF_CURRENT
fi

# ------------------------------------------------------------
# 3.3. 브라우저 번역 언어 자동 설정 (Chrome → 한국어)
#   chrome://settings/languages 에서 매번 "이 언어로 번역: 한국어" + "번역 안 함: 영어" 를
#   손으로 설정해야 하는 번거로움을 없앤다. Chrome 은 이 값을 프로필 폴더의
#   Preferences(JSON) 파일에 저장하므로(translate.enabled·translate_recent_target·
#   translate_blocked_languages), jq 로 미리 심어둔다.
#   리눅스 Chrome 의 프로필 위치는 ~/.config/google-chrome 이다(맥은 Library 아래).
#   크롬이 실행 중이면 종료할 때 메모리에 있던 설정으로 이 파일을 통째로 덮어써
#   심어둔 값이 되돌려진다 — 그래서 실행 중이면 건너뛰고 안내만 남긴다.
#   프로필이 아직 없으면(최초 설치, 한 번도 실행 안 함) Default 프로필 폴더를 새로 만들어
#   심어둔다 — 최초 실행 때 이 파일을 그대로 읽는다.
#
#   ※ 맥의 Dia 브라우저는 리눅스에 없어 생략 — 대체: Chrome 한 곳만 설정한다.
# ------------------------------------------------------------
log "3.3. 브라우저 번역 언어 자동 설정 (Chrome → 한국어로 자동 번역, 영어는 번역 안 함)"
if (( HAS_GUI != 0 )); then
  ok "데스크톱(GUI) 환경이 아니라 브라우저 설정을 건너뜁니다"
elif ! have jq; then
  warn "jq 없음 → Chrome 번역 언어 자동 설정 건너뜀 (위 3단계에서 jq 설치 실패)"
elif pgrep -x chrome >/dev/null 2>&1 || pgrep -x google-chrome >/dev/null 2>&1; then
  warn "Chrome 실행 중 → 번역 언어 자동 설정 건너뜀 (Chrome 을 완전히 종료한 뒤 스크립트를 다시 실행하세요)"
else
  chrome_profiles_dir="$HOME/.config/google-chrome"
  chrome_prefs="$chrome_profiles_dir/Default/Preferences"
  if mkdir -p "$chrome_profiles_dir/Default" 2>/dev/null; then
    [[ -f "$chrome_prefs" ]] || echo '{}' > "$chrome_prefs"
    chrome_tmp="$(mktemp)"
    if jq '.translate.enabled = true
           | .translate_recent_target = "ko"
           | .translate_blocked_languages = (((.translate_blocked_languages // []) + ["en"]) | unique)' \
         "$chrome_prefs" > "$chrome_tmp" 2>/dev/null && [[ -s "$chrome_tmp" ]]; then
      mv "$chrome_tmp" "$chrome_prefs"
      ok "Chrome 번역 언어 자동 설정 완료 (한국어로 번역, 영어는 번역 안 함)"
    else
      rm -f "$chrome_tmp"
      warn "Chrome 번역 언어 자동 설정 실패 → 건너뜀 (수동 설정: chrome://settings/languages 에서 직접 지정)"
    fi
    unset chrome_tmp
  else
    warn "Chrome 프로필 폴더를 만들지 못했습니다 → 번역 언어 자동 설정 건너뜀"
  fi
  unset chrome_profiles_dir chrome_prefs
fi

# ------------------------------------------------------------
# 3.4. GitHub 인증 자동화 (1Password 팀 공용 토큰 → gh auth login)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   coco-de 조직의 co-bricks·skills 레포는 비공개라서, 바로 아래 3.5단계(cocode-skills)와
#   4단계의 cob(co-bricks) 설치가 GitHub 로그인 없이는 실패한다. 예전에는 사람이 직접
#   'gh auth login' 을 실행해야 했는데, 이 단계가 팀 공용 1Password 토큰으로 대신
#   로그인해준다 — ZenHub·Jira 토큰 자동 주입(8.5·8.6단계)과 같은 방식이다.
#
#   [동작 전제]
#   1) op(1Password CLI) 설치 + 팀 계정 연결(TEAM_OP_ACCOUNT, 8.5단계와 공유) — 준비가
#      안 됐다면 8.5단계 안내를 먼저 따라 하면 이 단계도 함께 준비된다.
#      리눅스에서는 1Password 앱 > 설정 > 개발자 > '1Password CLI와 통합' 을 켜 두면
#      터미널에서 op 명령이 앱의 로그인 상태를 그대로 쓴다.
#   2) 1Password 팀 공용 항목: "API Token" 볼트 > "GitHub API Token" > credential 필드
#      (레포 최소 read 권한이면 충분한 Personal Access Token)
#
#   [멱등성]
#   'gh auth login' 을 이미 마친 사람(수동이든 이 단계든)은 매번 다시 로그인하지 않고 건너뛴다.
#
#   [비밀 취급]
#   토큰은 파일로 떨어뜨리지 않고 파이프로만 gh 에 넘기며, 쓰고 나서 바로 변수에서 지운다(unset).
#
#   [준비가 안 됐거나 실패해도]
#   ⚠ 후 계속 진행한다 — 아래 3.5단계와 4단계 cob 설치가 각자 gh 인증 상태를 다시 확인해
#   알맞게 건너뛰므로 전체 설치가 멈추지 않는다.
# ------------------------------------------------------------
log "3.4. GitHub 인증 자동화 (1Password → gh auth login)"
GITHUB_TOKEN_OP_REF="op://API Token/GitHub API Token/credential"  # 팀 공용 항목 경로 (토큰 값은 1Password에만 존재)
if have gh && gh auth status >/dev/null 2>&1; then
  ok "gh 이미 인증됨 (건너뜀)"
elif have gh && op_has_account; then
  gh_token="$(op_read "$GITHUB_TOKEN_OP_REF" </dev/null)" || gh_token=""
  if [[ -n "$gh_token" ]] \
     && printf '%s' "$gh_token" | gh auth login --hostname github.com --with-token >/dev/null 2>&1 \
     && gh auth setup-git >/dev/null 2>&1; then
    ok "1Password 토큰으로 gh 자동 로그인 완료 (git도 이 인증을 그대로 사용)"
  else
    warn "1Password에서 GitHub 토큰을 읽지 못했습니다 → 건너뜀 (수동: gh auth login)"
    info "※ 팀 공용 항목이 없다면 1Password 'API Token' 볼트에 'GitHub API Token'(credential 필드,"
    info "  레포 read 권한 PAT)을 만들어 주세요."
  fi
  unset gh_token
else
  warn "gh 미설치 또는 1Password 계정 미연결 → GitHub 인증 건너뜀 (수동: gh auth login)"
  info "1Password 앱 > 설정 > 개발자 > '1Password CLI와 통합' 을 켠 뒤 다시 실행하면 자동으로 로그인됩니다"
fi

# ------------------------------------------------------------
# 3.5. cocode-skills 팀 플러그인 설치 (사설 레포 coco-de/skills)
#   marionette·dart·figma(serve)·dev-cycle·coui 등 cc-* 플러그인 번들을 설치한다.
#   private 레포라 `claude plugin marketplace add` 가 안 되므로 팀 install.sh 로 동기화.
#   전제: gh 인증(gh auth login) + jq(위 3단계에서 설치) + rsync.
#   바로 위 3.4단계가 1Password 토큰으로 gh 자동 로그인을 먼저 시도하므로, 보통은 이
#   단계에 오기 전에 이미 인증돼 있다. 3.4가 실패했거나 건너뛴 경우에만 아래 else로 빠진다.
#
#   ⭐ rsync: 리눅스에는 기본으로 들어 있고(없으면 아래에서 apt 로 깐다), install.sh 가
#      맥에서와 똑같이 동작한다. 윈도우(co-win)에서는 rsync 가 없어 이 단계가 막혔지만
#      리눅스에는 그 문제가 없다 — 맥과 동일하게 그대로 실행하면 된다.
# ------------------------------------------------------------
log "3.5. cocode-skills 팀 플러그인 설치 (coco-de/skills install.sh)"
have rsync || apt_install rsync || warn "rsync 설치 실패 → cocode-skills 설치가 실패할 수 있습니다"
if have gh && gh auth status >/dev/null 2>&1; then
  cs_installer="$(mktemp)"
  if gh api repos/coco-de/skills/contents/install.sh --jq '.content' 2>/dev/null \
       | base64 -d > "$cs_installer" && [[ -s "$cs_installer" ]]; then
    bash "$cs_installer" \
      && ok "cocode-skills 팀 플러그인 설치 완료" \
      || warn "cocode-skills 설치 실패 → 건너뜀 (재시도: bash <(gh api repos/coco-de/skills/contents/install.sh --jq '.content' | base64 -d))"
  else
    warn "install.sh를 받지 못했습니다 (coco-de/skills 접근 권한 확인) → 건너뜀"
  fi
  rm -f "$cs_installer"
  unset cs_installer
else
  warn "gh 인증 필요 → 위 3.4단계(1Password 자동 로그인) 확인 또는 'gh auth login' 수동 실행 후"
  info "재실행하면 cocode-skills 팀 플러그인이 설치됩니다"
fi


# ------------------------------------------------------------
# 4-a. FVM + Flutter stable 글로벌 설치
#   FVM은 프로젝트마다 다른 Flutter 버전을 골라 쓰게 해 주는 도구다. 팀은 FVM으로 버전을
#   맞추므로 Flutter를 직접 내려받지 않고 FVM을 먼저 깐다.
# ------------------------------------------------------------
log "4-a. FVM 설치 및 Flutter stable 글로벌 설정"
if have fvm; then
  ok "fvm 이미 설치됨"
else
  # 맥은 Homebrew tap 으로 깔지만, 리눅스에는 fvm 을 담은 apt/snap 저장소가 없다.
  # → 공식 설치 스크립트를 쓴다. 이 스크립트는 fvm 본체를 ~/.fvm_flutter 에 풀고,
  #   관리자 권한이 있으면 /usr/local/bin/fvm 바로가기까지 만들어 준다.
  curl -fsSL https://fvm.app/install.sh | bash \
    || warn "fvm 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://fvm.app/install.sh | bash)"
fi
# 방금 깐 fvm 과, fvm 이 깔아 줄 dart/flutter 전역 명령을 이 스크립트가 바로 쓸 수 있게 한다.
#   (새 터미널용 PATH 설정은 8단계가 ~/.zshrc 에 따로 넣는다)
# fvm 설치 스크립트 2.0.0 부터 기본 설치 위치가 ~/fvm/bin 이다(~/.fvm_flutter 는 v1 경로로,
#   마이그레이션 과정에서 오히려 삭제된다). 옛 경로도 함께 넣어 v1 이 남은 PC 도 계속 동작하게 한다.
path_prepend "$HOME/.fvm_flutter/bin"
path_prepend "$HOME/fvm/bin"
path_prepend "$HOME/.pub-cache/bin"

if have fvm; then
  # `yes |` 는 설치 중 나오는 확인 질문에 자동으로 y를 눌러 준다 (사람이 지켜보지 않아도 진행).
  yes | fvm install stable || warn "Flutter stable 설치 실패 → 건너뜀 (수동 설치: fvm install stable)"
  yes | fvm global stable --force 2>/dev/null || yes | fvm global stable \
    || warn "Flutter stable 글로벌 설정 실패 → 건너뜀 (수동 설정: fvm global stable)"
  # fvm global 이 만든 기본 버전 바로가기(~/fvm/default/bin)에 flutter·dart 가 들어 있다.
  path_prepend "$HOME/fvm/default/bin"
else
  warn "fvm 을 찾지 못해 Flutter stable 설치를 건너뜁니다"
fi

# ------------------------------------------------------------
# 4-b. Dart 글로벌 패키지
#   본체(run_dart_packages_step)는 이 파일 앞부분에 정의돼 있다 — --dart-only 가 설치 단계를
#   건너뛰고 이 단계만 실행할 수 있어야 하기 때문이다.
# ------------------------------------------------------------
run_dart_packages_step

# ------------------------------------------------------------
# 4-c. Google Cloud CLI (gcloud)
#   Firebase·GCP 프로젝트를 터미널에서 다루는 구글 공식 도구.
# ------------------------------------------------------------
log "4-c. Google Cloud CLI 설치"
if have gcloud; then
  ok "gcloud 이미 설치됨"
else
  # 맥은 brew cask 로 깔지만, 리눅스는 구글이 직접 운영하는 apt 저장소를 등록해서 깐다.
  # (저장소로 깔아 두면 나중에 'sudo apt upgrade' 만으로 같이 최신이 된다)
  if add_apt_repo google-cloud-cli https://packages.cloud.google.com/apt/doc/apt-key.gpg \
       "https://packages.cloud.google.com/apt cloud-sdk main"; then
    apt_install google-cloud-cli || true
    have gcloud || {
      warn "gcloud 설치 실패 → 건너뜀 (수동 설치: sudo apt install google-cloud-cli)"
      info "(설치 안내: https://cloud.google.com/sdk/docs/install#deb)"
    }
  else
    warn "gcloud 저장소 등록 실패 → 설치를 건너뜁니다"
    info "(수동 설치 안내: https://cloud.google.com/sdk/docs/install#deb)"
  fi
fi

# ------------------------------------------------------------
# 4-d. DCM (Dart Code Metrics)
#   여기서는 dcm CLI 자체만 설치한다. CI/자동화 인증용 이메일+키(DCM_EMAIL·DCM_CI_KEY)는
#   ZenHub·Jira·Slang GPT 토큰처럼 1Password 팀 공용 항목에서 읽어 아래 8.8단계에서 주입한다.
# ------------------------------------------------------------
log "4-d. DCM 설치"
if have dcm; then
  ok "dcm 이미 설치됨"
else
  # 맥은 brew tap 을 신뢰 등록해서 깔지만, 리눅스는 DCM 공식 apt 저장소가 따로 있다.
  if add_apt_repo dcm https://dcm.dev/pgp-key.public "https://dcm.dev/debian stable main"; then
    apt_install dcm || true
  else
    warn "dcm 저장소 등록 실패 → 설치를 건너뜁니다"
  fi
  have dcm || {
    warn "dcm 설치 실패 → 건너뜀 (수동 설치: sudo apt install dcm)"
    info "(설치 안내: https://dcm.dev/docs/getting-started/)"
  }
fi

# ------------------------------------------------------------
# 4-e. Android SDK 구성요소 (cmdline-tools, platform-tools, build-tools, platforms, NDK, 에뮬레이터, AVD)
#   Android Studio(GUI)를 직접 실행해 SDK 설치 마법사를 거치지 않아도 되도록,
#   명령줄 도구(cmdline-tools)만으로 표준 SDK 위치($ANDROID_HOME)에 필요한 구성요소를 전부 설치한다.
#   ※ 리눅스에는 iOS 개발 도구(Xcode·CocoaPods)가 없어 안드로이드 쪽만 준비한다 —
#     대체: iOS 빌드는 맥(co-mac 으로 세팅한 PC)이나 CI 의 macOS 러너에서 한다.
# ------------------------------------------------------------
log "4-e. Android SDK 구성요소 설치 (cmdline-tools, platform-tools, build-tools, platforms, NDK, AVD)"

# 리눅스 표준 SDK 위치. Android Studio 리눅스판도 같은 경로를 쓰기 때문에,
# 나중에 Android Studio를 열어도 여기 깔린 구성요소를 그대로 인식한다.
# (맥의 ~/Library/Android/sdk 에 해당하는 자리다)
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
mkdir -p "$ANDROID_HOME" || warn "$ANDROID_HOME 폴더를 만들지 못했습니다"

# sdkmanager 는 자바(JDK)로 돌아가는 프로그램이라 JDK 17이 없으면 아예 실행되지 않는다.
#   맥은 `brew --prefix openjdk@17` 로 위치를 물어보지만, 데비안 계열은 아키텍처 이름이 붙은
#   고정 경로(/usr/lib/jvm/java-17-openjdk-amd64 · java-17-openjdk-arm64)에 깔린다.
#   openjdk-17-jdk 자체는 위 3단계가 설치한다.
ANDROID_JDK="/usr/lib/jvm/java-17-openjdk-$ARCH"
if [[ ! -d "$ANDROID_JDK" ]]; then
  # 배포판/아키텍처에 따라 폴더 이름이 조금 다를 수 있어 한 번 더 훑어본다.
  ANDROID_JDK="$(ls -d /usr/lib/jvm/java-17-openjdk-* 2>/dev/null | head -1 || true)"
fi

if [[ -z "$ANDROID_JDK" || ! -d "$ANDROID_JDK" ]]; then
  warn "JDK 17을 찾지 못해 Android SDK 설치를 건너뜁니다 (sdkmanager는 자바 없이 동작하지 않습니다)"
  info "(수동 설치: sudo apt install openjdk-17-jdk 를 실행한 뒤 './linux-setup.sh' 를 다시 돌려 주세요)"
else
  export JAVA_HOME="$ANDROID_JDK"
  path_prepend "$JAVA_HOME/bin"
  ok "JDK 17 사용: $JAVA_HOME"

  # ── cmdline-tools 설치 ─────────────────────────────────────
  # 맥은 brew cask(android-commandlinetools)로 부트스트랩한 뒤 정식 설치를 이어 갔지만,
  # 리눅스에는 그 역할을 할 패키지가 없다. → 구글 공식 zip 을 직접 받아 SDK 안에 배치한다.
  CMDLINE_TOOLS_HOME="$ANDROID_HOME/cmdline-tools/latest"
  if [[ -x "$CMDLINE_TOOLS_HOME/bin/sdkmanager" ]]; then
    ok "cmdline-tools 이미 설치됨 ($CMDLINE_TOOLS_HOME)"
  else
    have unzip || apt_install unzip || true
    # 파일 이름 가운데 숫자는 구글의 빌드 번호다. 번호가 올라가면 옛 주소는 사라지므로,
    # 알려진 번호를 최신순으로 시도해 먼저 받아지는 것을 쓴다.
    CMDLINE_TOOLS_ZIP="$(mktemp --suffix=.zip 2>/dev/null || mktemp)"
    CMDLINE_TOOLS_FETCHED=0
    for CT_VER in 13114758 12266719 11076708; do
      if curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CT_VER}_latest.zip" \
           -o "$CMDLINE_TOOLS_ZIP"; then
        CMDLINE_TOOLS_FETCHED=1
        break
      fi
    done
    if (( CMDLINE_TOOLS_FETCHED )) && have unzip; then
      CT_TMP="$(mktemp -d)"
      # zip 을 풀면 최상위 폴더 이름이 그냥 'cmdline-tools' 다. 그대로 두면 sdkmanager 가
      # 자기 위치를 잘못 계산해 "Could not determine SDK root" 로 실패하므로,
      # 그 폴더를 통째로 $ANDROID_HOME/cmdline-tools/latest 자리로 한 단계 옮겨 준다.
      if unzip -q -o "$CMDLINE_TOOLS_ZIP" -d "$CT_TMP" && [[ -d "$CT_TMP/cmdline-tools" ]]; then
        if mkdir -p "$ANDROID_HOME/cmdline-tools" \
             && rm -rf "$CMDLINE_TOOLS_HOME" \
             && mv "$CT_TMP/cmdline-tools" "$CMDLINE_TOOLS_HOME"; then
          ok "cmdline-tools 설치 완료 ($CMDLINE_TOOLS_HOME)"
        else
          warn "cmdline-tools 배치 실패 → 건너뜀"
        fi
      else
        warn "cmdline-tools 압축 해제 실패 → 건너뜀"
      fi
      rm -rf "$CT_TMP"
    else
      warn "cmdline-tools 내려받기 실패 → 건너뜀"
      info "(수동 설치: https://developer.android.com/studio#command-line-tools-only 에서 리눅스용 zip 을"
      info " 받아 $ANDROID_HOME/cmdline-tools/latest 에 풀어 주세요)"
    fi
    rm -f "$CMDLINE_TOOLS_ZIP"
  fi

  SDKMANAGER="$CMDLINE_TOOLS_HOME/bin/sdkmanager"
  AVDMANAGER="$CMDLINE_TOOLS_HOME/bin/avdmanager"

  if [[ -x "$SDKMANAGER" ]]; then
    # 안드로이드 SDK는 설치 전에 라이선스 동의가 필요하다 — 전부 y로 자동 동의한다.
    yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

    # 최신 안정 버전 자동 탐지 (프리뷰 채널 제외) — pyenv 최신 버전 탐지와 동일한 방식
    SDK_LIST="$("$SDKMANAGER" --sdk_root="$ANDROID_HOME" --list 2>/dev/null)" || true
    LATEST_PLATFORM=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*platforms;android-[0-9]+' | tr -d ' ' | sort -t'-' -k2 -n | tail -1)
    LATEST_BUILD_TOOLS=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*build-tools;[0-9]+\.[0-9]+\.[0-9]+' | tr -d ' ' | sort -t';' -k2 -V | tail -1)

    # NDK는 sdkmanager 목록의 '최신'이 아니라 Flutter가 요구하는 버전으로 고정한다.
    # (목록 최신값은 r30-beta 같은 프리뷰라 Flutter stable 빌드의 android.ndkVersion과 어긋나
    #  Gradle NDK 불일치를 유발한다. Flutter SDK에 박힌 핀 값을 그대로 사용한다.)
    FLUTTER_ROOT=""
    FLUTTER_NDK=""
    if have flutter; then
      FLUTTER_ROOT="$(cd "$(dirname "$(command -v flutter)")/.." 2>/dev/null && pwd || true)"
    fi
    if [[ -n "$FLUTTER_ROOT" ]]; then
      FLUTTER_NDK="$(grep -oE "ndkVersion = '[0-9.]+'" \
        "$FLUTTER_ROOT/packages/flutter_tools/lib/src/android/gradle_utils.dart" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    fi
    if [[ -n "$FLUTTER_NDK" ]]; then
      LATEST_NDK="ndk;$FLUTTER_NDK"
      info "· NDK: Flutter 요구 버전 사용 → $LATEST_NDK"
    else
      LATEST_NDK="ndk;28.2.13676358"
      warn "Flutter NDK 핀을 못 읽어 기본값 사용: $LATEST_NDK"
    fi

    # 에뮬레이터 시스템 이미지 ABI는 이 PC의 CPU와 맞아야 한다.
    #   ARM64 리눅스에서 x86_64 이미지를 고르면 통역(에뮬레이션)이 붙어 아예 부팅하지 못하거나
    #   쓸 수 없을 만큼 느리다. 그래서 0단계에서 확인한 ARCH 값으로 이미지를 고른다.
    if [[ "$ARCH" == "arm64" ]]; then
      ARCH_ABI="arm64-v8a"
    else
      ARCH_ABI="x86_64"
    fi
    # 에뮬레이터 시스템 이미지는 최신 platform보다 늦게 배포되기도 한다(예: android-37 platform은 있지만
    # 이미지는 미출시). 최신 platform 번호를 그대로 쓰면 없는 이미지를 받으려다 AVD 생성까지 실패하므로,
    # '실제로 존재하는' google_apis 이미지 중 가장 최신 API 버전을 골라 사용한다.
    IMAGE_API=$(echo "$SDK_LIST" | grep -oE "system-images;android-[0-9]+;google_apis;${ARCH_ABI}" \
      | sed -E 's/system-images;android-([0-9]+).*/\1/' | sort -n | tail -1)
    SYSTEM_IMAGE=""
    [[ -n "$IMAGE_API" ]] && SYSTEM_IMAGE="system-images;android-${IMAGE_API};google_apis;${ARCH_ABI}"

    PACKAGES=("platform-tools" "emulator")
    [[ -n "$LATEST_BUILD_TOOLS" ]] && PACKAGES+=("$LATEST_BUILD_TOOLS")
    [[ -n "$LATEST_PLATFORM" ]] && PACKAGES+=("$LATEST_PLATFORM")
    [[ -n "$SYSTEM_IMAGE" ]] && PACKAGES+=("$SYSTEM_IMAGE")
    [[ -n "$LATEST_NDK" ]] && PACKAGES+=("$LATEST_NDK")

    echo "  설치할 패키지: ${PACKAGES[*]}"
    # 패키지를 하나씩 설치해, 한 패키지가 실패해도 나머지 설치는 계속 진행되게 한다
    for PKG in "${PACKAGES[@]}"; do
      yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "$PKG" \
        || warn "$PKG 설치 실패 → 건너뜀"
    done

    # ANDROID_NDK_HOME은 실제 설치된 디스크 경로 기준으로 잡는다 (요구 버전 우선, 없으면 설치된 것 사용)
    WANT_NDK="${LATEST_NDK#ndk;}"
    if [[ -d "$ANDROID_HOME/ndk/$WANT_NDK" ]]; then
      export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$WANT_NDK"
    elif ls -d "$ANDROID_HOME"/ndk/*/ >/dev/null 2>&1; then
      ANDROID_NDK_HOME="$(ls -d "$ANDROID_HOME"/ndk/*/ | sort -V | tail -1)"
      export ANDROID_NDK_HOME="${ANDROID_NDK_HOME%/}"
    fi

    # AVD(안드로이드 가상 기기) 생성 (이미 있으면 건너뜀)
    #   이름은 실제 설치한 시스템 이미지의 API 버전을 따른다.
    if [[ -x "$AVDMANAGER" && -n "$SYSTEM_IMAGE" ]]; then
      AVD_NAME="Pixel_6_API_${IMAGE_API}"
      if "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD_NAME"; then
        ok "AVD($AVD_NAME) 이미 존재"
      else
        echo "no" | "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_6 \
          || warn "AVD 생성 실패 → 건너뜀 (Android Studio의 Device Manager에서 수동 생성 가능)"
      fi
    elif [[ -x "$AVDMANAGER" ]]; then
      warn "${ARCH_ABI}용 google_apis 시스템 이미지를 찾지 못해 AVD 생성을 건너뜁니다"
      [[ "$ARCH_ABI" == "arm64-v8a" ]] && info "(ARM64 리눅스는 제공되는 에뮬레이터 이미지가 적습니다 — 실제 기기 연결을 권합니다)"
    fi
  else
    warn "sdkmanager를 찾을 수 없어 Android SDK 구성요소 설치를 건너뜁니다"
  fi
fi

# ── 에뮬레이터 하드웨어 가속(KVM) ─────────────────────────────
#   맥은 애플이 만든 가속기(HVF)가 항상 켜져 있어 따로 할 일이 없지만, 리눅스는 KVM 이
#   준비돼 있어야 안드로이드 에뮬레이터가 쓸 만한 속도로 돈다.
#   ※ kvm·libvirt 그룹 가입(권한 부여)은 9단계가 맡는다 — 여기서는 확인과 패키지 설치까지만 한다.
if [[ -e /dev/kvm ]]; then
  ok "KVM 가상화 사용 가능 (/dev/kvm)"
  apt_install qemu-kvm libvirt-daemon-system \
    || warn "KVM 관련 패키지 설치 실패 → 건너뜀 (에뮬레이터가 느릴 수 있습니다)"
else
  warn "/dev/kvm 이 없어 에뮬레이터 하드웨어 가속을 쓸 수 없습니다"
  info "PC를 껐다 켠 뒤 BIOS(UEFI) 설정에서 가상화 기능(Intel VT-x · AMD-V/SVM)을 켜 주세요."
  info "(가상머신 안에서 실행 중이라면 호스트에서 중첩 가상화를 허용해야 합니다)"
  info "가속 없이도 에뮬레이터는 뜨지만 매우 느립니다 — 실제 안드로이드 기기 연결을 권합니다."
fi

# ============================================================
# 5 ~ 7.5단계 — Python(pyenv) · Node.js(nvm) · Claude Code 상태줄 · oh-my-zsh/p10k · 터미널 폰트
# ============================================================

# ------------------------------------------------------------
# 5. Python (pyenv로 최신 3.x)
#   맥에서는 brew로 pyenv를 깔지만, 우분투에는 brew가 없어 pyenv 공식 설치
#   스크립트(https://pyenv.run)를 쓴다. 설치 위치는 맥과 똑같이 ~/.pyenv 다.
# ------------------------------------------------------------
log "5. Python 최신 3.x 설치 (pyenv)"

# ⚠ 리눅스의 pyenv는 파이썬을 "미리 만들어진 파일"로 받지 않고 소스에서 직접 컴파일한다.
#   아래 라이브러리들이 없으면 빌드가 에러 없이 끝나 놓고도 ssl·sqlite3·lzma 같은 표준
#   기능이 통째로 빠진 반쪽짜리 파이썬이 깔린다(대표 증상: pip이 https를 못 써서 아무것도
#   설치하지 못함). 그래서 오래 걸리는 빌드를 시작하기 전에 여기서 먼저 채워 둔다.
#   0단계에서 깐 build-essential은 컴파일러만 주고, 이 라이브러리들은 주지 않는다.
info "파이썬 빌드에 필요한 라이브러리를 먼저 확인합니다 (없으면 반쪽짜리 파이썬이 깔립니다)"
apt_install libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
            libncursesw5-dev tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  || warn "파이썬 빌드 라이브러리 설치 실패 → 계속 진행 (파이썬 설치가 실패하거나 일부 기능이 빠질 수 있습니다)"

export PYENV_ROOT="$HOME/.pyenv"

if [[ -d "$PYENV_ROOT/bin" ]] || have pyenv; then
  ok "pyenv 이미 설치됨"
else
  # 공식 설치 스크립트가 ~/.pyenv 에 pyenv 본체와 빌드 플러그인을 한 번에 내려받는다.
  curl -fsSL https://pyenv.run | bash \
    || warn "pyenv 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://pyenv.run | bash)"
fi

# 지금 실행 중인 이 스크립트에서 바로 pyenv를 쓸 수 있게 PATH에 넣는다.
#   (새 터미널에서 쓰기 위한 ~/.zshrc 설정은 8단계가 따로 넣는다)
path_prepend "$PYENV_ROOT/bin"
path_prepend "$PYENV_ROOT/shims"
eval "$(pyenv init - 2>/dev/null)" 2>/dev/null || true

# 설치 가능한 3.x 목록 중 가장 최신(정식 버전만 — 3.13.0a1 같은 시험판은 걸러진다)
LATEST_PY="$(pyenv install --list 2>/dev/null | grep -E '^\s*3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ' || true)"

if ! have pyenv; then
  warn "pyenv를 불러오지 못했습니다 → Python 설치 건너뜀 (수동 설치: curl -fsSL https://pyenv.run | bash)"
elif [[ -z "$LATEST_PY" ]]; then
  warn "설치 가능한 파이썬 목록을 읽지 못했습니다 → 건너뜀 (수동 확인: pyenv install --list)"
else
  if pyenv versions --bare 2>/dev/null | grep -qx "$LATEST_PY"; then
    ok "Python $LATEST_PY 이미 설치됨"
  else
    info "Python $LATEST_PY 을(를) 소스에서 빌드합니다 — PC 성능에 따라 5~15분쯤 걸립니다."
    info "화면이 한동안 멈춘 것처럼 보여도 정상입니다. 그대로 기다려 주세요."
    pyenv install -s "$LATEST_PY" \
      || warn "Python $LATEST_PY 설치 실패 → 건너뜀 (수동 설치: pyenv install $LATEST_PY)"
  fi
  # 기본으로 쓸 파이썬 버전 지정 (~/.pyenv/version 파일에 기록된다)
  pyenv global "$LATEST_PY" 2>/dev/null \
    && ok "기본 Python 버전을 $LATEST_PY 로 지정" \
    || warn "Python 기본 버전 지정 실패 → 건너뜀 (수동 설정: pyenv global $LATEST_PY)"
fi

# ------------------------------------------------------------
# 6. Node.js (nvm으로 LTS, npm 포함)
#   맥에서는 brew로 nvm을 깔지만, 우분투에는 brew가 없어 nvm 공식 설치 스크립트를 쓴다.
#   버전을 v0.40.1로 못 박아 두는 이유: master를 그대로 받으면 어느 날 갑자기 동작이
#   바뀌어 팀원마다 다른 결과가 나올 수 있다.
# ------------------------------------------------------------
log "6. Node.js LTS 설치 (nvm, npm 포함)"

export NVM_DIR="$HOME/.nvm"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  ok "nvm 이미 설치됨"
else
  # 설치 스크립트가 ~/.bashrc·~/.zshrc 끝에 nvm 로딩 줄을 덧붙이는데, 팀 .zshrc에는
  # 이미 nvm 로딩이 들어 있고 8단계가 그 파일로 덮어쓰므로 신경 쓰지 않아도 된다.
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1 \
    && ok "nvm 설치 완료" \
    || warn "nvm 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash)"
fi

# nvm은 실행 파일이 아니라 "셸 함수"라서, 깔아 두기만 해서는 이 스크립트에서 부를 수 없다.
# nvm.sh를 지금 셸로 읽어들여야 아래 `nvm install`이 동작한다(맥 판도 같은 일을 한다).
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" 2>/dev/null || true
fi

if have nvm; then
  nvm install --lts \
    && ok "Node.js LTS 설치 완료" \
    || warn "Node.js LTS 설치 실패 → 건너뜀 (수동 설치: nvm install --lts)"
  nvm alias default 'lts/*' >/dev/null 2>&1 \
    && ok "기본 Node.js 버전을 LTS로 지정" \
    || warn "Node.js 기본 버전 지정 실패 → 건너뜀 (수동 설정: nvm alias default 'lts/*')"
else
  warn "nvm을 불러오지 못했습니다 → Node.js 설치 건너뜀 (위 nvm 설치가 실패했을 수 있습니다)"
fi

# ------------------------------------------------------------
# 6.1. codex 재시도 — 2.6단계에서 npm 이 없어 미뤄둔 항목
#   맥은 codex 를 Homebrew cask 로 깔아 순서 문제가 없지만, 리눅스는 npm 전역 설치라
#   Node 가 들어오는 6단계 이전에는 설치할 방법이 없다. 2.6단계는 그래서 안내만 남기고
#   건너뛰는데, 여기서 다시 시도하지 않으면 **전체 설치를 정상 완주해도 codex 는 영영 없다.**
# ------------------------------------------------------------
if have codex; then
  :   # 2.6단계에서 이미 설치됨(예전에 Node 를 깔아 둔 PC) — 조용히 넘어간다
elif have npm; then
  log "6.1. codex 설치 (2.6단계에서 Node.js 가 없어 미뤄둔 항목)"
  npm install -g @openai/codex >/dev/null 2>&1 \
    && ok "codex 설치 완료 (최초 실행 시 codex 로 ChatGPT 로그인)" \
    || warn "codex 설치 실패 → 건너뜀 (수동 설치: npm install -g @openai/codex)"
fi

# ------------------------------------------------------------
# 6.5. Claude Code 상태줄(statusline) — ccstatusline → Awesome CC Statusline(small)
#   1차: ccstatusline은 모델·세션 비용·컨텍스트 사용량·git 상태까지 보여주는
#   대화형 TUI 도구다(Node.js 기반, npx로 그때그때 실행 — 별도 설치 불필요:
#   https://github.com/sirmalloc/ccstatusline). 대화형이라 이 스크립트가 값을
#   자동으로 채워 넣을 수 없어, stdin을 막고 한 번 시도만 해 본다(실패해도 무해).
#   2차: 대화형이라 위 시도는 거의 항상 등록에 실패한다 — 그 경우 Awesome CC
#   Statusline을 size=small로 완전 비대화형 설치한다
#   (https://github.com/AwesomeJun/CC-statusline). 크기를 인자로 넘기면 프롬프트
#   없이 바로 ~/.claude/settings.json에 등록된다. jq 의존성은 3단계(CLI 도구)에서
#   이미 설치돼 있다.
#   두 도구 모두 같은 statusLine 키를 쓰므로, 나중에 다른 크기/도구로 바꾸고
#   싶으면 ~/.claude/settings.json의 statusLine 키를 지우고 원하는 쪽을 다시
#   실행하면 된다.
#   ※ 둘 다 node/네트워크가 필요하므로 6단계(Node.js) 바로 뒤에 둔다.
# ------------------------------------------------------------
log "6.5. Claude Code 상태줄 확인 (ccstatusline 시도 → 실패 시 Awesome CC Statusline(small)로 자동 대체)"

if ! have npx; then
  warn "npm(npx)이 없어 상태줄 설정을 건너뜁니다 (6단계 Node.js 설치가 실패했을 수 있습니다)"
  info "나중에 Node.js를 깔고 나서 'npx -y ccstatusline@latest' 를 직접 실행하면 됩니다"
elif grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
  ok "상태줄 이미 등록됨 (~/.claude/settings.json)"
else
  npx -y ccstatusline@latest </dev/null >/dev/null 2>&1 || true
  if grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
    ok "상태줄 등록 완료 (ccstatusline, ~/.claude/settings.json — Claude Code에서 바로 적용)"
  else
    info "↳ ccstatusline은 대화형 TUI라 자동 등록되지 않음 → Awesome CC Statusline(small)로 자동 설치 시도"
    if curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh 2>/dev/null | bash -s -- small >/dev/null 2>&1; then
      ok "상태줄 등록 완료 (Awesome CC Statusline, size: small — ~/.claude/settings.json)"
    else
      warn "상태줄 자동 등록 실패 → 사람이 직접 설정해야 합니다 (수동 설정: npx -y ccstatusline@latest 또는 curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh | bash -s -- small, 아래 '다음 단계' 참고)"
    fi
  fi
fi

# ------------------------------------------------------------
# 7. oh-my-zsh + powerlevel10k + 플러그인
#   맥에는 zsh가 기본으로 깔려 있지만 우분투/데비안에는 없을 수 있다 —
#   zsh가 없으면 oh-my-zsh 설치 스크립트가 곧바로 실패하므로 여기서 먼저 확인한다.
# ------------------------------------------------------------
log "7. oh-my-zsh 설치"

if ! have zsh; then
  info "zsh가 없어 먼저 설치합니다 (oh-my-zsh·powerlevel10k가 zsh 위에서 동작합니다)"
  apt_install zsh || true
fi

if ! have zsh; then
  warn "zsh를 설치하지 못했습니다 → oh-my-zsh·powerlevel10k 건너뜀 (수동 설치: sudo apt install zsh)"
elif [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "oh-my-zsh 이미 설치됨"
else
  # RUNZSH=no  : 설치가 끝난 뒤 zsh 셸로 갈아타지 않게 막는다. 이걸 빼면 스크립트가
  #              그 zsh 안에 갇혀 8단계 이후가 영영 실행되지 않는다.
  # CHSH=no    : 기본 셸을 여기서 바꾸지 않게 막는다(암호를 물어 멈출 수 있다).
  #              기본 셸 변경은 8단계가 따로 처리한다.
  # KEEP_ZSHRC : 기존 ~/.zshrc를 백업으로 밀어내지 않고 그대로 둔다(8단계가 팀 설정을 넣는다).
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && ok "oh-my-zsh 설치 완료" \
    || warn "oh-my-zsh 설치 실패 → 건너뜀 (테마·플러그인도 함께 건너뛸 수 있습니다)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

log "7. powerlevel10k + 플러그인 설치"

if ! have git; then
  warn "git이 없어 powerlevel10k·플러그인 설치를 건너뜁니다 (수동 설치: sudo apt install git)"
else
  # "이름|주소|받을 위치" 형식. 이미 폴더가 있으면 손대지 않는다 —
  # 팀원이 직접 손본 설정을 git pull로 덮어쓰지 않기 위해서다(업데이트는 각자 필요할 때).
  P10K_REPOS=(
    "powerlevel10k 테마|https://github.com/romkatv/powerlevel10k.git|$ZSH_CUSTOM/themes/powerlevel10k"
    "zsh-autosuggestions 플러그인|https://github.com/zsh-users/zsh-autosuggestions|$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    "zsh-syntax-highlighting 플러그인|https://github.com/zsh-users/zsh-syntax-highlighting.git|$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    "powerlevel10k(~/powerlevel10k)|https://github.com/romkatv/powerlevel10k.git|$HOME/powerlevel10k"
  )
  for P10K_ENTRY in "${P10K_REPOS[@]}"; do
    P10K_NAME="${P10K_ENTRY%%|*}"
    P10K_REST="${P10K_ENTRY#*|}"
    P10K_URL="${P10K_REST%%|*}"
    P10K_DEST="${P10K_REST##*|}"
    if [[ -d "$P10K_DEST" ]]; then
      ok "$P10K_NAME 이미 설치됨 (최신으로 올리려면 해당 폴더에서 git pull)"
    else
      git clone --depth=1 "$P10K_URL" "$P10K_DEST" >/dev/null 2>&1 \
        && ok "$P10K_NAME 설치 완료" \
        || warn "$P10K_NAME 내려받기 실패 → 건너뜀"
    fi
  done
  # ~/powerlevel10k 를 따로 한 번 더 받는 이유: 팀 .zshrc가 그 경로를 직접 source 한다.
fi

# ------------------------------------------------------------
# 7.5. 터미널 폰트 자동 적용 (MesloLGS NF)
#   powerlevel10k 프롬프트의 화살표·아이콘은 전용 폰트(MesloLGS NF)가 있어야 제대로 보인다.
#   그런데 폰트를 "설치"만 해서는 소용이 없다 — 터미널 앱이 실제로 그 폰트를 쓰도록
#   프로필에서 골라 줘야 한다. 그래서 두 가지를 함께 한다.
#     1) 폰트 4종(Regular·Bold·Italic·Bold Italic)을 ~/.local/share/fonts 에 설치
#        (맥은 brew cask로 깔지만 리눅스에는 그런 게 없어 공식 배포처에서 직접 받는다)
#     2) 우분투 기본 터미널인 GNOME Terminal이면 기본 프로필 폰트를 자동으로 바꿔 준다
#        (맥에서 Terminal.app을 osascript로 건드리던 부분에 해당한다)
#   Konsole·Alacritty 등 다른 터미널은 자동화 대상이 아니라 안내만 한다.
#   화면(데스크톱)이 없는 서버 환경이면 이 단계는 통째로 의미가 없어 건너뛴다.
# ------------------------------------------------------------
log "7.5. 터미널 폰트 자동 적용 (MesloLGS NF)"

if [[ "$HAS_GUI" -ne 0 ]]; then
  ok "화면(데스크톱)이 없는 환경 → 터미널 폰트 단계 건너뜀"
else
  MESLO_DIR="$HOME/.local/share/fonts"
  MESLO_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
  MESLO_FILES=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
  )

  mkdir -p "$MESLO_DIR" 2>/dev/null || warn "폰트 폴더($MESLO_DIR) 생성 실패 → 폰트 설치가 실패할 수 있습니다"

  MESLO_NEW=0
  for MESLO_FILE in "${MESLO_FILES[@]}"; do
    if [[ -f "$MESLO_DIR/$MESLO_FILE" ]]; then
      ok "$MESLO_FILE 이미 설치됨"
    else
      # 파일 이름에 공백이 있어 주소에서는 %20 으로 바꿔야 한다.
      MESLO_URL="$MESLO_BASE/${MESLO_FILE// /%20}"
      if curl -fsSL "$MESLO_URL" -o "$MESLO_DIR/$MESLO_FILE" 2>/dev/null; then
        ok "$MESLO_FILE 설치 완료"
        MESLO_NEW=1
      else
        rm -f "$MESLO_DIR/$MESLO_FILE"    # 반쯤 받다 만 파일이 남으면 다음 실행에서 "이미 있음"으로 오해한다
        warn "$MESLO_FILE 내려받기 실패 → 건너뜀"
      fi
    fi
  done

  # 새로 받은 폰트가 있으면 폰트 목록 캐시를 갱신해야 터미널이 그 폰트를 알아본다.
  if [[ "$MESLO_NEW" -eq 1 ]]; then
    if have fc-cache; then
      fc-cache -f "$MESLO_DIR" >/dev/null 2>&1 \
        && ok "폰트 캐시 갱신 완료" \
        || warn "폰트 캐시 갱신 실패 → 건너뜀 (수동 실행: fc-cache -f)"
    else
      warn "fc-cache가 없어 폰트 캐시를 갱신하지 못했습니다 (수동 설치: sudo apt install fontconfig)"
    fi
  fi

  # --- 터미널 프로필에 폰트 적용 (GNOME Terminal만 자동) ---
  if ! have gsettings; then
    warn "gsettings가 없어 터미널 폰트 자동 적용을 건너뜁니다"
    info "터미널 설정(환경설정 > 프로필)에서 폰트를 'MesloLGS NF'로 직접 바꿔 주세요"
  elif ! gsettings list-schemas 2>/dev/null | grep -qx "org.gnome.Terminal.ProfilesList"; then
    info "GNOME Terminal이 아닌 터미널(Konsole·Alacritty 등)입니다 → 자동 적용 건너뜀"
    info "사용 중인 터미널 설정에서 폰트를 'MesloLGS NF'로 직접 바꿔 주세요"
  else
    # 기본 프로필의 UUID를 읽는다. gsettings는 값을 'xxxx-...' 처럼 작은따옴표로 감싸
    # 돌려주므로, 따옴표를 벗겨야 아래 경로에 끼워 넣을 수 있다.
    GT_PROFILE="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null || true)"
    GT_PROFILE="${GT_PROFILE//\'/}"
    if [[ -z "$GT_PROFILE" ]]; then
      warn "GNOME Terminal 기본 프로필을 찾지 못했습니다 → 자동 적용 건너뜀 (환경설정 > 프로필 > 사용자 지정 글꼴에서 'MesloLGS NF' 선택)"
    else
      GT_PATH="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${GT_PROFILE}/"
      # use-system-font이 켜져 있으면 시스템 기본 글꼴이 우선이라 font 값이 무시된다.
      # 그래서 먼저 끄고 나서 폰트를 지정해야 실제로 적용된다.
      if gsettings set "$GT_PATH" use-system-font false 2>/dev/null \
         && gsettings set "$GT_PATH" font "MesloLGS NF 12" 2>/dev/null; then
        ok "GNOME Terminal 기본 프로필 폰트를 'MesloLGS NF 12'로 적용 (새 터미널 창부터 반영됩니다)"
      else
        warn "GNOME Terminal 폰트 자동 적용 실패 → 건너뜀 (환경설정 > 프로필 > 사용자 지정 글꼴에서 'MesloLGS NF' 선택)"
      fi
    fi
  fi
fi


fi   # ← if (( ! ENV_ONLY )) 끝: 1~7.5단계 블록 종료
     #   여기부터(8단계~)는 --env-only 로 실행해도 함께 돈다.


# ------------------------------------------------------------
# 8. ~/.zshrc / ~/.p10k.zsh 반영
#    - 스크립트 옆에 기존 PC의 .zshrc/.p10k.zsh가 있으면 그대로 복사
#    - 옆에 둘 다 없었다면 0.5단계가 레포에서 받아둔 것을 복사 (DOTFILE_DIR가 그쪽을 가리킴)
#    - 그것도 없으면 아래 기본 설정 생성
#
#    ⚠ 팀 .zshrc 는 맥에서 쓰던 파일이라 맥 전용 경로(/opt/homebrew/…, ~/Library/Android/sdk)가
#      들어 있다. 그대로 두면 리눅스에서 자바·안드로이드 SDK·문법 하이라이트가 전부 동작하지
#      않으므로, 복사한 뒤 리눅스 경로로 자동 변환한다(아래 linuxize_zshrc).
#
#    --env-only 실행 시에는 이 단계를 건너뛴다 (토큰만 다시 주입하는 모드이므로
#    사용자가 그동안 손본 ~/.zshrc 를 덮어쓰면 안 된다).
# ------------------------------------------------------------

# ~/.zshrc 안의 맥 전용 경로를 리눅스 경로로 바꾼다.
#   반환값: 0=변환함 · 2=바꿀 것이 없음(이미 변환됨) · 1=실패
#   ⚠ 반드시 멱등이어야 한다 — 스크립트를 두 번, 세 번 돌려도 결과가 같아야 하므로
#     '맥 경로를 리눅스 경로로 바꾸는' 방향으로만 치환한다(바꾼 뒤에는 찾을 대상이 사라진다).
linuxize_zshrc() {
  local f="$HOME/.zshrc" tmp="$HOME/.zshrc.linux.tmp" jdk="" cand
  # ARCH 가 비어 있으면(헤더가 dpkg 를 못 읽은 경우) 가장 흔한 amd64로 가정한다 —
  # 빈 값이 그대로 들어가면 'java-17-openjdk-' 같은 있을 수 없는 경로가 박힌다.
  local arch="${ARCH:-amd64}"

  [[ -f "$f" ]] || return 1
  # 맥 흔적이 하나도 없으면 이미 변환된(또는 원래 리눅스용) 파일이다 — 그냥 둔다.
  grep -qE '/opt/homebrew|Library/Android/sdk|brew shellenv|brew --prefix' "$f" 2>/dev/null || return 2

  # JAVA_HOME 으로 쓸 자바 17 경로를 찾는다. apt 로 깐 openjdk-17 은 아키텍처 이름이 붙는다
  #   (amd64: java-17-openjdk-amd64 · arm64: java-17-openjdk-arm64).
  for cand in "/usr/lib/jvm/java-17-openjdk-${arch}" /usr/lib/jvm/java-17-openjdk-* \
              /usr/lib/jvm/temurin-17-jdk* /usr/lib/jvm/java-1.17.0-*; do
    if [[ -d "$cand" ]]; then jdk="$cand"; break; fi
  done
  [[ -n "$jdk" ]] || jdk="/usr/lib/jvm/java-17-openjdk-${arch}"   # 아직 안 깔렸어도 표준 경로로 적어 둔다

  if sed \
      -e "s%/opt/homebrew/share/zsh-syntax-highlighting/%/usr/share/zsh-syntax-highlighting/%g" \
      -e "s%/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home%${jdk}%g" \
      -e "s%/opt/homebrew/opt/openjdk@17%${jdk}%g" \
      -e "s%Library/Android/sdk%Android/Sdk%g" \
      -e "s%[\$](brew --prefix nvm)%\$NVM_DIR%g" \
      -e "s%^\([[:space:]]*\).*brew shellenv.*%\1true  # Homebrew 설정 제거 — 리눅스에서는 apt/snap 을 쓴다%" \
      -e "s%^\([[:space:]]*\).*brew --prefix.*%\1true  # Homebrew 설정 제거 — 리눅스에서는 apt/snap 을 쓴다%" \
      -e "\%^[[:space:]]*\[\[ -d /opt/homebrew/opt/gradle@7%d" \
      -e "\%^[[:space:]]*\[\[ -d /opt/homebrew/opt/libpq%d" \
      -e "\%^[[:space:]]*\[\[ -d /opt/homebrew/opt/node@22%d" \
      "$f" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv "$tmp" "$f"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

if (( ! ENV_ONLY )); then

log "8. ~/.zshrc 설정 (팀 셸 설정 반영 + 기본 셸을 zsh로)"

# 0.5단계가 DOTFILE_DIR 을 정해 두지 못했다면(그 단계를 건너뛴 경우) 스크립트 옆 폴더를 본다.
DOTFILE_DIR="${DOTFILE_DIR:-$SCRIPT_DIR}"

# ⚠ 이미 ~/.p10k.zsh 가 있으면 덮어쓰지 않는다.
#   스크립트가 스스로 안내하는 `p10k configure` 로 프롬프트를 손봐 둔 팀원이 재실행하면
#   그 결과가 조용히 사라지기 때문이다(README 는 "몇 번을 실행해도 안전"하다고 약속한다).
#   팀 기본값으로 되돌리고 싶으면 ~/.p10k.zsh 를 지우고 다시 실행하면 된다.
if [[ -f "$HOME/.p10k.zsh" ]] && ! [[ "$DOTFILE_DIR/.p10k.zsh" -ef "$HOME/.p10k.zsh" ]]; then
  ok ".p10k.zsh 이미 있음 → 그대로 둡니다 (팀 기본값으로 되돌리려면 ~/.p10k.zsh 를 지우고 다시 실행)"
elif copy_dotfile "$DOTFILE_DIR/.p10k.zsh" "$HOME/.p10k.zsh" ".p10k.zsh"; then
  :   # copy_dotfile이 결과 메시지를 직접 출력한다
elif [[ ! -f "$HOME/.p10k.zsh" ]]; then
  # 기존 PC에서 .p10k.zsh를 가져오지 않은 새 PC: powerlevel10k 기본 설정을 복사한다.
  # 이게 없으면 새 셸마다 설정 마법사(p10k configure)가 떠서 "세팅이 정상적이지 않게" 보인다.
  P10K_DEFAULT="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k/config/p10k-lean.zsh"
  if [[ -f "$P10K_DEFAULT" ]]; then
    cp "$P10K_DEFAULT" "$HOME/.p10k.zsh" && ok "기본 .p10k.zsh 생성 완료 (p10k-lean, 설정 마법사 생략)" \
      || warn ".p10k.zsh 복사 실패 → 새 셸에서 'p10k configure' 직접 실행 필요"
  else
    warn "p10k 기본 설정 템플릿을 찾지 못함 — 새 셸에서 'p10k configure' 직접 실행 필요"
  fi
fi

if [[ -f "$DOTFILE_DIR/.zshrc" ]]; then
  # 원본과 대상이 같은 파일이면 복사도 백업도 하지 않는다 — 자기 자신을 자기 위에 복사하면
  # cp가 오류로 끝나고 set -e에 걸려 스크립트가 여기서 멈춰버린다.
  # (아래 호환 패치는 어느 경우든 그대로 적용한다 — 모두 멱등이라 두 번 걸려도 안전하다)
  if [[ "$DOTFILE_DIR/.zshrc" -ef "$HOME/.zshrc" ]]; then
    ok ".zshrc 이미 제자리에 있음 (복사 생략)"
  else
    # ── 이미 주입돼 있던 팀 토큰 줄을 먼저 건져 둔다 ──
    #   아래에서 팀 원본 .zshrc 로 통째로 덮어쓰는데, 팀 원본에는 토큰 줄이 없다.
    #   보통은 8.5~8.9단계가 이 실행에서 다시 주입하지만, 1Password 가 잠겨 있거나
    #   비대화형이면 그 단계가 건너뛰어져 **토큰이 통째로 사라진다**(도구 하나 추가하려고
    #   재실행했다가 ZenHub·Jira MCP 가 전부 끊기는 사고). 그래서 덮어쓰기 직후 되돌린다.
    PRESERVED_TOKENS="$(grep -E '^export (ZENHUB_API_TOKEN|JIRA_API_TOKEN|SLANG_GPT_API_KEY|DCM_EMAIL|DCM_CI_KEY|SLACK_TEAM_ID|SLACK_BOT_TOKEN)=' "$HOME/.zshrc" 2>/dev/null || true)"

    if [[ -f "$HOME/.zshrc" ]]; then
      ZSHRC_BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
      # 백업본에는 팀 공용 토큰이 평문으로 들어 있다 — 남들이 읽지 못하게 권한을 조인다.
      if cp "$HOME/.zshrc" "$ZSHRC_BACKUP" 2>/dev/null; then
        chmod 600 "$ZSHRC_BACKUP" 2>/dev/null || true
        # 실행할 때마다 쌓이면 토큰 사본이 홈에 수십 개 남는다 — 최근 5개만 남기고 지운다.
        ls -1t "$HOME"/.zshrc.backup.* 2>/dev/null | tail -n +6 | while read -r old_backup; do
          rm -f "$old_backup" 2>/dev/null || true
        done
      fi
      unset ZSHRC_BACKUP
    fi

    # cp 실패(예: 예전에 sudo 로 편집해 ~/.zshrc 가 root 소유가 된 PC)를 받지 않으면
    #   set -e 에 걸려 스크립트가 8단계에서 그대로 죽는다.
    if cp "$DOTFILE_DIR/.zshrc" "$HOME/.zshrc" 2>/dev/null; then
      # 건져 둔 토큰 줄을 되돌린다. 8.5~8.9단계가 이어서 돌면 각자 strip 후 최신값으로 다시 넣으므로
      # 중복되지 않는다(멱등).
      if [[ -n "$PRESERVED_TOKENS" ]]; then
        printf '\n%s\n' "$PRESERVED_TOKENS" >> "$HOME/.zshrc"
        ok "이미 주입돼 있던 팀 토큰을 보존했습니다"
      fi
    else
      warn ".zshrc 복사 실패 → 기존 파일을 그대로 둡니다 (소유자·권한을 확인해 주세요)"
      info "수동 확인: ls -l ~/.zshrc   (root 소유라면: sudo chown $(id -un) ~/.zshrc)"
    fi
    unset PRESERVED_TOKENS
  fi

  # --- 리눅스 경로 변환 (팀 .zshrc 는 맥에서 쓰던 파일이다) ---
  LINUXIZE_RC=0
  linuxize_zshrc || LINUXIZE_RC=$?
  case "$LINUXIZE_RC" in
    0) ok "팀 .zshrc 를 리눅스 경로로 변환해 반영했습니다" ;;
    2) ok "팀 .zshrc 를 리눅스 경로로 변환해 반영했습니다 (이미 변환돼 있어 바뀐 곳 없음)" ;;
    *) warn "리눅스 경로 변환 실패 → .zshrc 는 그대로 두었습니다 (자바·안드로이드 경로를 직접 고쳐야 할 수 있습니다)" ;;
  esac

  # --- 리눅스 호환 패치 ---
  # 미설치 도구를 무조건 source 하는 라인 → 파일 존재 시에만 source 하도록 가드
  sed -i 's|^\. "\$HOME/.local/bin/env"|[[ -f "$HOME/.local/bin/env" ]] \&\& . "$HOME/.local/bin/env"|' "$HOME/.zshrc" 2>/dev/null || true
  sed -i 's|^eval "\$(direnv hook zsh)"|command -v direnv >/dev/null \&\& eval "$(direnv hook zsh)"|' "$HOME/.zshrc" 2>/dev/null || true

  # PATH 중복 증식 방지: 터미널을 중첩해서 열 때마다 같은 경로가 쌓이는 것을 막는다.
  #   예전 PC의 .zshrc를 그대로 가져오는 경우 이 설정이 없어서 셸을 열 때마다 PATH가
  #   10개 이상씩 늘어난다(3단계만 겹쳐도 40개 육박 → 명령 탐색이 느려짐).
  #   이미 있으면 건너뛴다 — 멱등.
  #   (sed 삽입은 구현체마다 문법이 달라 실패하기 쉬우므로 임시파일 방식을 쓴다)
  if ! grep -q '^typeset -U path' "$HOME/.zshrc" 2>/dev/null; then
    if {
      echo '# PATH 중복 제거 — 터미널을 중첩해서 열어도 같은 경로가 쌓이지 않게 한다 (linux-setup 자동 추가)'
      echo 'typeset -U path fpath PATH FPATH'
      cat "$HOME/.zshrc"
    } > "$HOME/.zshrc.tmp" 2>/dev/null && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"; then
      ok "PATH 중복 제거 설정 추가"
    else
      rm -f "$HOME/.zshrc.tmp"
      warn "PATH 중복 제거 설정 추가 실패 — 무시하고 계속합니다"
    fi
  fi
  ok ".zshrc 반영 완료 (덮어썼다면 기존 파일은 백업됨, 리눅스 호환 패치 적용)"
elif [[ -f "$HOME/.zshrc" ]] && grep -q 'powerlevel10k' "$HOME/.zshrc" 2>/dev/null; then
  # 팀 .zshrc 를 못 받았는데(네트워크 일시 오류 등) 이미 세팅이 끝난 PC인 경우다.
  #   여기서 최소 기본값으로 덮어쓰면 지난 실행의 결과와 토큰이 통째로 날아간다 — 그냥 둔다.
  ok "기존 ~/.zshrc 를 그대로 둡니다 (팀 설정을 내려받지 못했지만 이미 설정이 들어 있습니다)"
  info "팀 최신 설정으로 맞추려면 네트워크 확인 후 다시 실행해 주세요"
else
  [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
  # 팀 설정을 못 구했을 때만 쓰는 최소 기본값. 팀 .zshrc 를 받아오면 이 파일은 덮어써진다.
  cat > "$HOME/.zshrc" <<'ZSHRC'
# ===== PATH 중복 제거 =====
typeset -U path fpath PATH FPATH

# ===== Powerlevel10k instant prompt =====
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===== oh-my-zsh =====
export ZSH="$HOME/.oh-my-zsh"
# ~/.p10k.zsh 가 없더라도 설정 마법사가 자동으로 뜨지 않게 한다(정상 프롬프트로 시작).
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions)
source $ZSH/oh-my-zsh.sh
# 문법 하이라이트는 apt 패키지(zsh-syntax-highlighting)로 설치된다 — 맥의 Homebrew 경로와 다르다.
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ===== Java 17 (apt openjdk-17-jdk) =====
# 아키텍처(amd64/arm64)마다 폴더 이름이 달라, 있는 것을 찾아 잡는다.
for _jdk in /usr/lib/jvm/java-17-openjdk-*; do
  if [[ -d "$_jdk" ]]; then
    export JAVA_HOME="$_jdk"
    export PATH="$JAVA_HOME/bin:$PATH"
    break
  fi
done
unset _jdk

# ===== FVM / Flutter · Dart =====
export PATH="$HOME/fvm/default/bin:$PATH"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PUB_CACHE/bin:$PATH"

# ===== Go =====
export GOPATH="$HOME/go"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"

# ===== Python (pyenv) =====
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

# ===== Node (nvm) =====
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# ===== Android SDK =====
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
if [[ -d "$ANDROID_HOME" ]]; then
  export PATH="$ANDROID_HOME/platform-tools:$PATH"
  export PATH="$ANDROID_HOME/emulator:$PATH"
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
fi

# ===== Google Cloud SDK =====
[[ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]] && . "$HOME/google-cloud-sdk/path.zsh.inc"
[[ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]] && . "$HOME/google-cloud-sdk/completion.zsh.inc"

# ===== direnv =====
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

# ===== Claude Code (공식 인스톨러, ~/.local/bin) =====
export PATH="$HOME/.local/bin:$PATH"

# ===== powerlevel10k config =====
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
ZSHRC
  ok "기본 .zshrc 생성 완료 (팀 설정을 못 받아 최소 구성으로 만들었습니다 · 기존 파일은 백업됨)"
fi

# Claude Code 공식 인스톨러 경로(~/.local/bin) PATH 보장
#   위에서 ~/.zshrc를 새로 만들거나 기존 파일로 교체하므로, 공식 인스톨러가 넣어줬을 수
#   있는 PATH 설정이 사라질 수 있다. 새 터미널에서도 claude가 바로 실행되도록
#   ~/.zshrc 확정 후 PATH 라인이 없으면 추가한다(이미 있으면 건너뜀 — 멱등).
if ! grep -qE '^[[:space:]]*export PATH=.*\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
  {
    echo ''
    echo '# ===== Claude Code (공식 인스톨러, ~/.local/bin) ====='
    echo 'export PATH="$HOME/.local/bin:$PATH"'
  } >> "$HOME/.zshrc"
  ok "~/.zshrc에 ~/.local/bin PATH 추가 (Claude Code)"
fi

# ------------------------------------------------------------
# 기본 셸을 zsh로 변경
#   위에서 만든 ~/.zshrc(테마·PATH·별칭)는 zsh로 로그인할 때만 읽힌다. 우분투 기본 셸은
#   bash라서, 이 변경을 하지 않으면 "설치는 다 됐는데 프롬프트가 그대로"인 상태가 된다.
#   ⚠ chsh 는 '다음 로그인'부터 적용된다 — 지금 열려 있는 터미널은 그대로 bash다.
# ------------------------------------------------------------
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
if [[ -z "$ZSH_BIN" ]]; then
  warn "zsh 가 설치돼 있지 않아 기본 셸 변경을 건너뜁니다 (수동 설치: sudo apt install zsh)"
else
  CURRENT_SHELL="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  [[ -n "$CURRENT_SHELL" ]] || CURRENT_SHELL="${SHELL:-}"
  if [[ "$CURRENT_SHELL" == *zsh ]]; then
    ok "기본 셸이 이미 zsh 입니다 ($CURRENT_SHELL)"
  else
    # chsh 는 /etc/shells 에 등록된 셸만 받아준다. snap/직접 빌드로 깐 zsh 는 빠져 있을 수 있다.
    if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
      if need_sudo && echo "$ZSH_BIN" | $SUDO tee -a /etc/shells >/dev/null 2>&1; then
        ok "/etc/shells 에 $ZSH_BIN 등록 (기본 셸로 지정할 수 있게)"
      else
        warn "/etc/shells 에 $ZSH_BIN 이 없어 기본 셸 변경이 실패할 수 있습니다"
        info "수동 실행: echo $ZSH_BIN | sudo tee -a /etc/shells"
      fi
    fi
    # sudo 가 이미 확보돼 있으면 그쪽을 먼저 쓴다 — 암호를 다시 묻지 않아 비대화형에서도 통과한다.
    if need_sudo && $SUDO chsh -s "$ZSH_BIN" "$(id -un)" >/dev/null 2>&1; then
      ok "기본 셸을 zsh 로 변경했습니다 (로그아웃했다 다시 로그인하면 적용됩니다)"
      NEED_RELOGIN=1
    # ⚠ </dev/null 이 없으면, 암호를 물어보는 chsh 가 프롬프트를 /dev/null 로 버린 채
    #   입력을 무한정 기다려 스크립트가 멈춘 것처럼 보인다.
    elif chsh -s "$ZSH_BIN" </dev/null >/dev/null 2>&1; then
      ok "기본 셸을 zsh 로 변경했습니다 (로그아웃했다 다시 로그인하면 적용됩니다)"
      NEED_RELOGIN=1
    else
      warn "기본 셸 변경 실패 → 건너뜀 (비대화형 실행이거나 암호 입력이 필요한 경우입니다)"
      info "수동 실행: chsh -s $ZSH_BIN     (암호를 물어봅니다 · 로그아웃 후 적용)"
      info "그전까지는 터미널에서 'zsh' 를 입력하면 팀 설정이 적용된 셸을 바로 써볼 수 있습니다"
    fi
  fi
fi

fi  # ══ 8단계 끝 — 여기부터(8.5~8.9 토큰 주입)는 --env-only 실행 시에도 수행된다 ══

# --env-only 가드: 아직 전체 세팅을 한 번도 하지 않은 PC면 토큰을 붙일 ~/.zshrc 골격이
#   없다. 빈 .zshrc를 새로 만들어 토큰만 꽂으면 PATH·테마 등이 빠진 반쪽짜리 설정이 되므로,
#   전체 설치를 먼저 하도록 안내하고 종료한다.
if (( ENV_ONLY )) && [[ ! -f "$HOME/.zshrc" ]]; then
  echo ""
  echo "❌ ~/.zshrc 가 없습니다 — 아직 전체 세팅을 한 번도 하지 않은 PC로 보입니다."
  echo "   먼저 옵션 없이 전체 설치를 실행해 주세요: ./linux-setup.sh"
  exit 1
fi

# ------------------------------------------------------------
# 8.5. ZENHUB_API_TOKEN 주입 (팀 공용 토큰 — 1Password에서 자동 주입)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   ZenHub(이슈 보드)를 Claude Code에서 쓰려면 '토큰'이라는 비밀번호 같은 값이 필요하다.
#   이 값을 사람마다 복사·붙여넣기하지 않도록, 팀 공용 1Password 금고에 넣어 두고
#   1Password CLI(`op`)로 읽어 ~/.zshrc에 자동으로 적어준다.
#   (`op` = 1Password를 터미널에서 쓰는 명령. 1Password 앱과 같은 금고를 본다.)
#   토큰 값은 1Password에만 있고 git에는 절대 커밋되지 않는다.
#   실행 순서상 8단계에서 .zshrc가 확정된 뒤에 실행한다.
#
#   [동작 전제]
#   1) op(1Password CLI) 설치됨 — 1단계에서 설치
#   2) 1Password 앱(리눅스 데스크톱 버전)에 팀 계정(team-cocodeinc)으로 로그인
#   3) 1Password 앱 > 설정 > 개발자 > 'Integrate with 1Password CLI(1Password CLI와 통합)' 체크
#      → 이 통합을 켜야 op가 앱의 로그인 세션을 그대로 빌려 쓴다.
#        (안 켜면 op는 등록된 계정이 없어 실패한다. 'op account add'를 직접 할 필요는 없다.)
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "ZenHub API Token" > credential 필드
#     (계정이 여러 개인 사용자도 동작하도록 --account로 팀 계정을 명시)
#   ※ 팀 계정 식별자(TEAM_OP_ACCOUNT)와 op_has_account()는 3.4단계보다 앞서 있어야 해서
#     헤더에 정의돼 있다 — 이 단계는 그걸 그대로 재사용한다.
#
#   [준비가 안 됐을 때]
#   터미널(TTY)이면 여기서 멈춰 한글 안내를 띄우고, 1Password 설정을 마친 뒤 Enter로 재시도한다.
#   파이프 실행(TTY 없음)이면 멈추지 않고 건너뜀(설정 후 스크립트 재실행 시 자동 주입).
# ------------------------------------------------------------
ZENHUB_TOKEN_OP_REF="op://API Token/ZenHub API Token/credential"      # 팀 공용 항목 경로 (값은 1Password에만 존재)
# jira MCP(mcp-atlassian)도 같은 팀 계정·같은 볼트의 토큰을 쓴다 (아래 8.6단계에서 주입).
#   자격증명은 개발팀 공용 계정(dev@cocode.im)의 Jira 개인 API 토큰(ATATT…)이며,
#   mcp-atlassian이 JIRA_USERNAME+JIRA_API_TOKEN으로 Basic 인증을 내부 처리하므로
#   ~/.zshrc에는 raw 토큰만 JIRA_API_TOKEN으로 주입한다(zenhub와 동일한 단순 패턴).
JIRA_TOKEN_OP_REF="op://API Token/Laputa Atlassian API Token/Jira API Token"  # 팀 공용 항목 경로 (토큰 값은 1Password에만 존재)
# slang_gpt(다국어 자동 번역 CLI)용 GPT 키도 같은 팀 계정·같은 볼트에서 읽는다 (아래 8.7단계에서 주입).
#   MCP 인증용이 아니라 slang_gpt가 셸 환경변수 SLANG_GPT_API_KEY를 직접 읽는 순수 환경변수라
#   claude mcp 등록 단계는 없다.
SLANG_GPT_TOKEN_OP_REF="op://API Token/Slang GPT API Token/credential"  # 팀 공용 항목 경로 (키 값은 1Password에만 존재)
# DCM(Dart 코드 품질 검사)의 CI 라이선스 인증용 '이메일 + 키'도 같은 팀 계정·같은 볼트에서 읽는다 (아래 8.8단계에서 주입).
#   MCP 인증용이 아니라 dcm CLI가 셸 환경변수 DCM_EMAIL·DCM_CI_KEY를 직접 읽어 CI 모드로 활성화하는
#   순수 환경변수라 claude mcp 등록 단계는 없다. 한 항목("DCM CI CD")의 두 필드를 각각 읽는다.
DCM_EMAIL_OP_REF="op://API Token/DCM CI CD/username"     # 팀 공용 항목의 이메일 필드 (값은 1Password에만 존재)
DCM_CI_KEY_OP_REF="op://API Token/DCM CI CD/credential"  # 팀 공용 항목의 CI 키 필드 (값은 1Password에만 존재)
# slack MCP(@modelcontextprotocol/server-slack)용 토큰도 같은 팀 계정·같은 볼트에서 읽는다 (아래 8.9단계에서 주입).
#   한 항목("Cocode Slack")의 두 필드(SLACK_TEAM_ID·SLACK_BOT_TOKEN)를 DCM과 동일하게 각각 읽는다.
SLACK_TEAM_ID_OP_REF="op://API Token/Cocode Slack/SLACK_TEAM_ID"      # 팀 공용 항목의 팀 ID 필드 (값은 1Password에만 존재)
SLACK_BOT_TOKEN_OP_REF="op://API Token/Cocode Slack/SLACK_BOT_TOKEN"  # 팀 공용 항목의 봇 토큰 필드 (값은 1Password에만 존재)

# ~/.zshrc에서 기존 ZENHUB_API_TOKEN 라인을 모두 제거한다.
#   빈 값(export ZENHUB_API_TOKEN="")이 남아 있으면 zenhub MCP가 인증 없이 뜨면서
#   `claude mcp list`에는 '✔ Connected'로 보이지만 실제 호출은 "Missing Authorization token"으로
#   실패한다 — 조용히 잘못된 상태가 되므로 빈 줄도 반드시 걷어낸다.
strip_zenhub_token_lines() {
  touch "$HOME/.zshrc"
  # sed 치환은 토큰 특수문자에 취약하므로 grep -v로 줄 단위 제거
  { grep -v '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" || true; } > "$HOME/.zshrc.tmp"
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
}

# ~/.zshrc의 ZENHUB_API_TOKEN 라인이 '존재하지만 값이 비어 있는' 상태인지 확인. 그렇다면 0.
#   ""/''/따옴표 없음을 모두 처리해야 해서 정규식 대신 셸 파라미터 확장으로 값을 벗겨낸다
#   (정규식으로 빈 문자열 대안을 표현하면 grep 구현체에 따라 에러가 난다).
zenhub_token_line_is_empty() {
  local line val
  line="$(grep '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 1        # 라인 자체가 없으면 정리할 것도 없음
  val="${line#export ZENHUB_API_TOKEN=}"
  val="${val#\"}"; val="${val%\"}"    # 큰따옴표 제거
  val="${val#\'}"; val="${val%\'}"    # 작은따옴표 제거
  [[ -z "$val" ]]
}

# op read → ~/.zshrc의 ZENHUB_API_TOKEN 주입. 성공 시 0, 실패 시 1 반환.
#   ⚠ op 호출에는 반드시 stdin을 </dev/null로 막는다.
#     계정이 등록되지 않은 상태의 op는 "Do you want to add an account manually now? [Y/n]"
#     프롬프트를 띄우고 입력을 기다려 스크립트가 그대로 멈춰버린다. 이 프롬프트는 /dev/tty에
#     직접 출력되기 때문에 2>/dev/null로도 가려지지 않는다. stdin을 막으면 op는 대기 없이
#     즉시 종료코드 1로 실패하고, 아래 안내 루프가 사람이 읽을 수 있는 설명을 대신 보여준다.
#   ⚠ 읽어 들인 토큰 변수는 주입 직후 unset 한다 — 이후 단계의 화면 출력이나 오류 메시지에
#     비밀값이 섞여 나가지 않게 하기 위함이다.
inject_zenhub_token() {
  local tok
  op_has_account || return 1
  tok="$(op read --account "$TEAM_OP_ACCOUNT" "$ZENHUB_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$tok" ]] || { unset tok; return 1; }
  strip_zenhub_token_lines
  printf 'export ZENHUB_API_TOKEN=%q\n' "$tok" >> "$HOME/.zshrc"
  unset tok
}

# ── jira MCP(mcp-atlassian) 토큰 헬퍼 — 위 ZenHub 3형제와 동일 패턴 ──────────────
#   op 계정 준비(앱 CLI 통합)는 ZenHub 단계에서 이미 처리되므로, 여기서는 계정 안내를
#   반복하지 않고 '주입 시도 + 정확한 경고'만 한다. mcp-atlassian이 이메일+토큰으로 Basic을
#   내부 처리하므로 ~/.zshrc에는 raw 토큰만 JIRA_API_TOKEN으로 넣는다(zenhub와 동일하게 단순).
strip_jira_token_lines() {
  touch "$HOME/.zshrc"
  { grep -v '^export JIRA_API_TOKEN=' "$HOME/.zshrc" || true; } > "$HOME/.zshrc.tmp"
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
}

jira_token_line_is_empty() {
  local line val
  line="$(grep '^export JIRA_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 1
  val="${line#export JIRA_API_TOKEN=}"
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  [[ -z "$val" ]]
}

inject_jira_token() {
  local tok
  op_has_account || return 1
  tok="$(op read --account "$TEAM_OP_ACCOUNT" "$JIRA_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$tok" ]] || { unset tok; return 1; }
  strip_jira_token_lines
  printf 'export JIRA_API_TOKEN=%q\n' "$tok" >> "$HOME/.zshrc"
  unset tok
}

# ── slang_gpt 번역 키 헬퍼 — 위 ZenHub·Jira와 동일 패턴 ──────────────
#   slang_gpt(Flutter 다국어 자동 번역 CLI)가 셸 환경변수 SLANG_GPT_API_KEY를 직접 읽는다.
#   MCP 등록이 없는 순수 환경변수라 주입 3형제만 있으면 된다.
strip_slang_gpt_token_lines() {
  touch "$HOME/.zshrc"
  { grep -v '^export SLANG_GPT_API_KEY=' "$HOME/.zshrc" || true; } > "$HOME/.zshrc.tmp"
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
}

slang_gpt_token_line_is_empty() {
  local line val
  line="$(grep '^export SLANG_GPT_API_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 1
  val="${line#export SLANG_GPT_API_KEY=}"
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  [[ -z "$val" ]]
}

inject_slang_gpt_token() {
  local tok
  op_has_account || return 1
  tok="$(op read --account "$TEAM_OP_ACCOUNT" "$SLANG_GPT_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$tok" ]] || { unset tok; return 1; }
  strip_slang_gpt_token_lines
  printf 'export SLANG_GPT_API_KEY=%q\n' "$tok" >> "$HOME/.zshrc"
  unset tok
}

# ── DCM CI 인증(이메일+키) 헬퍼 — 위 Slang GPT와 동일 패턴, 단 한 항목에서 두 필드를 읽는다 ──
#   dcm(Dart Code Metrics) CLI가 셸 환경변수 DCM_EMAIL·DCM_CI_KEY를 직접 읽어 CI 모드로 라이선스를
#   활성화한다. MCP 등록이 없는 순수 환경변수라 주입 헬퍼만 있으면 된다. 두 값이 모두 있어야
#   인증되므로 주입은 둘 다 읽는 데 성공했을 때만 한다(반쪽 인증 상태 방지).
strip_dcm_token_lines() {
  touch "$HOME/.zshrc"
  # DCM_EMAIL·DCM_CI_KEY 두 라인을 함께 걷어낸다 (grep -v 두 번 파이프)
  { grep -v '^export DCM_EMAIL=' "$HOME/.zshrc" | grep -v '^export DCM_CI_KEY=' || true; } > "$HOME/.zshrc.tmp"
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
}

# DCM_EMAIL·DCM_CI_KEY 중 하나라도 '라인은 있는데 값이 비어 있음'이면 0 (정리 대상). 둘 다 없거나
#   둘 다 값이 있으면 1. 빈 값이 남으면 dcm이 키를 읽은 것처럼 동작하다 인증만 실패하기 때문.
dcm_token_line_is_empty() {
  local line val var
  for var in DCM_EMAIL DCM_CI_KEY; do
    line="$(grep "^export ${var}=" "$HOME/.zshrc" 2>/dev/null | tail -1)"
    [[ -n "$line" ]] || continue        # 라인 자체가 없으면 이 변수는 정리할 것 없음
    val="${line#export ${var}=}"
    val="${val#\"}"; val="${val%\"}"    # 큰따옴표 제거
    val="${val#\'}"; val="${val%\'}"    # 작은따옴표 제거
    [[ -z "$val" ]] && return 0
  done
  return 1
}

inject_dcm_token() {
  local email key
  op_has_account || return 1
  email="$(op read --account "$TEAM_OP_ACCOUNT" "$DCM_EMAIL_OP_REF" 2>/dev/null </dev/null)" || return 1
  key="$(op read --account "$TEAM_OP_ACCOUNT" "$DCM_CI_KEY_OP_REF" 2>/dev/null </dev/null)" || { unset email; return 1; }
  [[ -n "$email" && -n "$key" ]] || { unset email key; return 1; }   # 둘 다 있어야 주입 (반쪽 인증 방지)
  strip_dcm_token_lines
  printf 'export DCM_EMAIL=%q\n' "$email" >> "$HOME/.zshrc"
  printf 'export DCM_CI_KEY=%q\n' "$key" >> "$HOME/.zshrc"
  unset email key
}

# ── slack MCP 토큰(SLACK_TEAM_ID·SLACK_BOT_TOKEN) 헬퍼 — 위 DCM과 동일 패턴, 한 항목에서 두 필드 ──
#   slack MCP(@modelcontextprotocol/server-slack)가 두 환경변수를 모두 요구하므로 DCM과 동일하게
#   둘 다 읽었을 때만 주입한다(반쪽 인증 방지).
strip_slack_token_lines() {
  touch "$HOME/.zshrc"
  { grep -v '^export SLACK_TEAM_ID=' "$HOME/.zshrc" | grep -v '^export SLACK_BOT_TOKEN=' || true; } > "$HOME/.zshrc.tmp"
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
}

slack_token_line_is_empty() {
  local line val var
  for var in SLACK_TEAM_ID SLACK_BOT_TOKEN; do
    line="$(grep "^export ${var}=" "$HOME/.zshrc" 2>/dev/null | tail -1)"
    [[ -n "$line" ]] || continue
    val="${line#export ${var}=}"
    val="${val#\"}"; val="${val%\"}"
    val="${val#\'}"; val="${val%\'}"
    [[ -z "$val" ]] && return 0
  done
  return 1
}

inject_slack_token() {
  local team_id bot_token
  op_has_account || return 1
  team_id="$(op read --account "$TEAM_OP_ACCOUNT" "$SLACK_TEAM_ID_OP_REF" 2>/dev/null </dev/null)" || return 1
  bot_token="$(op read --account "$TEAM_OP_ACCOUNT" "$SLACK_BOT_TOKEN_OP_REF" 2>/dev/null </dev/null)" || { unset team_id; return 1; }
  [[ -n "$team_id" && -n "$bot_token" ]] || { unset team_id bot_token; return 1; }   # 둘 다 있어야 주입 (반쪽 인증 방지)
  strip_slack_token_lines
  printf 'export SLACK_TEAM_ID=%q\n' "$team_id" >> "$HOME/.zshrc"
  printf 'export SLACK_BOT_TOKEN=%q\n' "$bot_token" >> "$HOME/.zshrc"
  unset team_id bot_token
}

log "8.5. ZENHUB_API_TOKEN 주입 (1Password 공용 토큰)"
# 값이 빈 기존 라인은 먼저 걷어낸다 — 남겨두면 zenhub MCP가 '연결됨'처럼 보이면서
# 실제 호출만 조용히 실패한다. 주입에 성공하면 어차피 새 값으로 다시 기록된다.
if zenhub_token_line_is_empty; then
  strip_zenhub_token_lines
  echo "  · 값이 비어 있던 기존 ZENHUB_API_TOKEN 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

# 1Password CLI 설정 방법을 화면에 그대로 안내한다.
#   이 문구는 '왜 필요한지 → 무엇을 누르면 되는지 → 어떻게 확인하는지' 순서로 읽히도록 유지한다.
print_1password_cli_guide() {
  echo ""
  echo "  ⏸  ZenHub 토큰을 가져오려면 1Password CLI 설정이 필요합니다."
  echo ""
  echo "     [무엇을 하는 건가요?]"
  echo "     ZenHub를 쓰려면 비밀번호 같은 '토큰' 값이 필요합니다. 이 값은 팀 공용 1Password 금고에"
  echo "     들어 있고, 1Password CLI(op)가 그 금고를 대신 열어 읽어옵니다. 아래 설정은 op에게"
  echo "     '1Password 앱에 이미 로그인된 상태를 그대로 써도 된다'고 허락해 주는 과정입니다."
  echo "     (토큰 값은 1Password에만 저장되고, 이 저장소(git)에는 절대 들어가지 않습니다.)"
  echo ""
  echo "     [설정 방법 — 1Password 앱(리눅스 데스크톱)에서]"
  echo "       1) 1Password 앱을 열고 팀 계정($TEAM_OP_ACCOUNT)으로 로그인"
  echo "       2) 앱 메뉴 > 설정(Ctrl+,) > '개발자' 탭 > '1Password CLI와 통합' 체크"
  echo "          · '개발자' 탭이 안 보이면: 설정 > 보안 > '시스템 인증으로 잠금 해제'를 먼저 켜세요"
  echo "          · 터미널을 이미 열어둔 상태였다면 체크 후 이 창에서 Enter만 누르면 됩니다"
  echo ""
  echo "     [잘 됐는지 확인하려면 — 새 터미널 창에서]"
  echo "       op account list   ← 팀 계정($TEAM_OP_ACCOUNT)이 목록에 보이면 성공"
  echo "                            · 목록이 비어 있거나 '계정을 추가할까요?'라고 물으면"
  echo "                              위 2번 체크가 아직 안 된 것입니다 (질문에는 n으로 답하세요)"
  echo "                            · 몇 초~수십 초 멈추면 1Password 앱이 잠금 해제를 기다리는"
  echo "                              중입니다 — 1Password 창에서 승인하면 진행됩니다"
  echo ""
  echo "     ※ 'op account add'를 직접 입력할 필요는 없습니다 — 앱 통합을 켜면 계정이 자동 등록됩니다."
  echo "     ※ 1Password 앱이 아니라 CLI만 설치된 경우(서버·헤드리스)에는 앱 통합을 쓸 수 없습니다."
  echo "        그때는 'op account add' 로 계정을 직접 등록한 뒤 다시 시도해 주세요."
  echo "     ※ 계정 목록에는 보이는데 계속 실패한다면, 팀 'API Token' 금고 접근 권한이 없는 경우입니다."
  echo "        이때는 팀 관리자에게 해당 금고 공유를 요청해 주세요."
  echo ""
}

# 10단계 검증 출력에서 재사용할 op 상태. 여기서 한 번만 판정한다 —
# op 호출은 1Password 앱 승인을 기다릴 수 있어 검증 단계에서 다시 부르면 또 멈춘다.
#   missing = op 미설치 · not-ready = 설치됐지만 앱 CLI 통합/권한 미완료 · ready = 토큰까지 읽힘
OP_STATUS="missing"

if ! have op; then
  warn "op(1Password CLI) 미설치 → ZENHUB_API_TOKEN 수동 설정 필요"
  info "(1단계에서 1password-cli 설치가 실패한 경우입니다 — 설치한 뒤 './linux-setup.sh --env-only' 를 실행하면 토큰만 다시 주입됩니다)"
elif inject_zenhub_token; then
  OP_STATUS="ready"
  ok "ZENHUB_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
elif [[ -t 0 ]]; then
  OP_STATUS="not-ready"
  # 대화형: 1Password 로그인 + CLI 통합을 마칠 때까지 멈춰서 안내 → Enter로 재시도
  while true; do
    print_1password_cli_guide
    printf "     설정을 마쳤으면 Enter(재시도) · 나중에 하려면 s 입력 후 Enter: "
    read -r zh_ans || zh_ans="s"
    if [[ "$zh_ans" == "s" || "$zh_ans" == "S" ]]; then
      warn "ZENHUB_API_TOKEN 주입 건너뜀 → 1Password 설정을 마친 뒤 './linux-setup.sh --env-only' 로 토큰만 다시 주입할 수 있습니다"
      break
    fi
    if inject_zenhub_token; then
      OP_STATUS="ready"
      ok "ZENHUB_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
      break
    fi
    # 어느 단계에서 막혔는지 짚어준다 — 계정 자체가 없으면 앱 통합이, 있으면 금고 권한이 원인이다.
    if op_has_account; then
      echo "  ✗ 계정은 등록됐지만 토큰을 읽지 못했습니다."
      echo "     → 팀 계정($TEAM_OP_ACCOUNT)으로 로그인된 상태인지, 'API Token' 금고에"
      echo "       접근 권한이 있는지 확인한 뒤 다시 Enter를 누르세요."
    else
      echo "  ✗ 아직 op에 등록된 1Password 계정이 없습니다."
      echo "     → 위 [설정 방법]의 2번('1Password CLI와 통합' 체크)이 켜졌는지 확인한 뒤 다시 Enter를 누르세요."
    fi
  done
else
  # 비대화형(TTY 없음): 멈추지 않고 건너뜀
  OP_STATUS="not-ready"
  warn "op read 실패(비대화형) → 아래 1Password CLI 설정을 마친 뒤 './linux-setup.sh --env-only' 를 실행하면 토큰만 자동 주입됩니다"
  info "1) 1Password 앱에 팀 계정($TEAM_OP_ACCOUNT)으로 로그인"
  info "2) 앱 > 설정(Ctrl+,) > 개발자 > '1Password CLI와 통합' 체크"
  info "3) 확인: op account list  (팀 계정이 보이면 성공)"
fi

# ------------------------------------------------------------
# 8.6. JIRA_API_TOKEN 주입 (개발팀 공용 계정 Jira 토큰 — 1Password에서 자동 주입)
#   ZenHub와 동일한 방식. op 계정 설정(앱 CLI 통합)은 위 8.5에서 이미 안내·처리됐으므로
#   여기서는 그 안내를 반복하지 않고 '주입 시도 + 원인별 경고'만 한다.
#   자격증명은 개발팀 공용 계정(dev@cocode.im)의 Jira 토큰(팀 "API Token" 볼트 > "Laputa Atlassian API Token" > "Jira API Token" 필드).
#   mcp-atlassian(Docker)이 JIRA_USERNAME+JIRA_API_TOKEN으로 Basic 인증을 내부 처리하므로 raw 토큰만 주입한다.
# ------------------------------------------------------------
log "8.6. JIRA_API_TOKEN 주입 (1Password 공용 계정 Jira 토큰, mcp-atlassian용)"
# 주입 여부는 10단계 검증에서 ~/.zshrc의 JIRA_API_TOKEN 값(JIRA_VAL)으로 직접 판단한다.

# 값이 빈 기존 라인은 먼저 걷어낸다 (ZenHub와 동일 — 빈 값이 남으면 MCP가 '연결됨'처럼 보이며 호출만 실패)
if jira_token_line_is_empty; then
  strip_jira_token_lines
  echo "  · 값이 비어 있던 기존 JIRA_API_TOKEN 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  warn "op(1Password CLI) 미설치 → JIRA_API_TOKEN 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './linux-setup.sh --env-only' 실행)"
elif inject_jira_token; then
  ok "JIRA_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
else
  # op가 준비됐는데도 못 읽었다면 대개 팀 'API Token' 볼트 접근 권한이 없거나 항목/필드명이 다른 경우.
  if op_has_account; then
    warn "JIRA_API_TOKEN 미주입 — 1Password에서 'Laputa Atlassian API Token > Jira API Token'을 읽지 못했습니다."
    info "확인하세요:"
    info "  1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    info "  2) 볼트에 'Laputa Atlassian API Token' 항목 + 'Jira API Token' 필드가 있는지"
    info "확인 후 './linux-setup.sh --env-only' 를 실행하면 토큰만 다시 주입됩니다 (그전까지 jira MCP는 미주입 상태)."
  else
    warn "JIRA_API_TOKEN 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    info "op(1Password CLI) 설정을 마친 뒤 './linux-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
  fi
fi

# ------------------------------------------------------------
# 8.7. SLANG_GPT_API_KEY 주입 (slang_gpt 다국어 자동 번역용 GPT 키 — 1Password에서 자동 주입)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   Flutter 앱의 다국어(한국어·영어…) 문구를 자동으로 번역해 주는 도구 slang_gpt가
#   GPT 서비스를 부를 때 쓰는 '키'가 필요하다. ZenHub·Jira 토큰과 똑같이 팀 공용
#   1Password 금고에서 읽어 ~/.zshrc에 적어준다.
#
#   ZenHub(8.5)·Jira(8.6)와 동일한 방식이며, op 계정 설정(앱 CLI 통합) 안내는 8.5에서
#   이미 처리했으므로 여기서는 반복하지 않고 '주입 시도 + 원인별 경고'만 한다.
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "Slang GPT API Token" > credential 필드
#   ※ 이 값은 MCP 인증용이 아니라 slang_gpt CLI가 환경변수로 직접 읽는 값이라
#     claude mcp 등록 단계가 없다 (그래서 10단계 검증도 'mcp:' 형태가 아닌 단순 주입 여부만 표시).
# ------------------------------------------------------------
log "8.7. SLANG_GPT_API_KEY 주입 (1Password 공용 키, slang_gpt 다국어 자동 번역용)"

# 값이 빈 기존 라인은 먼저 걷어낸다 (ZenHub·Jira와 동일 — 빈 값이 남으면 도구가 키를 읽은 것처럼
# 동작하다 호출만 실패한다)
if slang_gpt_token_line_is_empty; then
  strip_slang_gpt_token_lines
  echo "  · 값이 비어 있던 기존 SLANG_GPT_API_KEY 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  warn "op(1Password CLI) 미설치 → SLANG_GPT_API_KEY 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './linux-setup.sh --env-only' 실행)"
elif inject_slang_gpt_token; then
  ok "SLANG_GPT_API_KEY 주입 완료 (~/.zshrc, 키 값은 커밋되지 않음)"
else
  if op_has_account; then
    warn "SLANG_GPT_API_KEY 미주입 — 1Password에서 'Slang GPT API Token > credential'을 읽지 못했습니다."
    info "확인하세요:"
    info "  1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    info "  2) 볼트에 'Slang GPT API Token' 항목 + 'credential' 필드가 있는지"
    info "확인 후 './linux-setup.sh --env-only' 를 실행하면 키만 다시 주입됩니다 (그전까지 slang_gpt 번역은 사용 불가)."
  else
    warn "SLANG_GPT_API_KEY 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    info "op(1Password CLI) 설정을 마친 뒤 './linux-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
  fi
fi

# ------------------------------------------------------------
# 8.8. DCM_EMAIL·DCM_CI_KEY 주입 (DCM CI 라이선스 인증용 이메일+키 — 1Password에서 자동 주입)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   Dart 코드 품질 검사 도구 DCM을 CI/자동화 모드로 인증할 때 쓰는 '이메일 + 키' 한 쌍이 필요하다.
#   ZenHub·Jira·Slang GPT와 똑같이 팀 공용 1Password 금고에서 읽어 ~/.zshrc에 적어준다.
#   dcm CLI가 이 두 환경변수(DCM_EMAIL·DCM_CI_KEY)를 직접 읽어 라이선스를 활성화하므로(MCP 아님)
#   별도 등록·로그인 과정이 없다.
#
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "DCM CI CD"
#       · 사용자명(username) 필드 = DCM_EMAIL(이메일)
#       · 자격 증명(credential) 필드 = DCM_CI_KEY(CI 키)
#   ※ 두 값이 모두 있어야 인증되므로, 하나라도 못 읽으면 아무것도 주입하지 않는다(반쪽 인증 방지).
# ------------------------------------------------------------
log "8.8. DCM_EMAIL·DCM_CI_KEY 주입 (1Password 공용 항목 'DCM CI CD', DCM CI 라이선스 인증용)"

# 값이 빈 기존 라인은 먼저 걷어낸다 (다른 토큰과 동일 — 빈 값이 남으면 dcm이 키를 읽은 것처럼
# 동작하다 인증만 조용히 실패한다)
if dcm_token_line_is_empty; then
  strip_dcm_token_lines
  echo "  · 값이 비어 있던 기존 DCM_EMAIL/DCM_CI_KEY 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  warn "op(1Password CLI) 미설치 → DCM_EMAIL·DCM_CI_KEY 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './linux-setup.sh --env-only' 실행)"
elif inject_dcm_token; then
  ok "DCM_EMAIL·DCM_CI_KEY 주입 완료 (~/.zshrc, 값은 커밋되지 않음)"
else
  if op_has_account; then
    warn "DCM_EMAIL·DCM_CI_KEY 미주입 — 1Password에서 'DCM CI CD'의 사용자명(username)/자격 증명(credential)을 읽지 못했습니다."
    info "확인하세요:"
    info "  1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    info "  2) 볼트에 'DCM CI CD' 항목 + 사용자명(username)·자격 증명(credential) 필드가 있는지"
    info "확인 후 './linux-setup.sh --env-only' 를 실행하면 값만 다시 주입됩니다 (그전까지 DCM CI 인증은 사용 불가)."
  else
    warn "DCM_EMAIL·DCM_CI_KEY 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    info "op(1Password CLI) 설정을 마친 뒤 './linux-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
  fi
fi

# ------------------------------------------------------------
# 8.9. SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (slack MCP용 팀 공용 토큰 — 1Password에서 자동 주입)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   slack MCP(2.5단계에서 등록)가 Slack 워크스페이스에 접속할 때 쓰는 '팀 ID + 봇 토큰' 한 쌍이
#   필요하다. ZenHub·Jira·Slang GPT·DCM과 똑같이 팀 공용 1Password 금고에서 읽어 ~/.zshrc에 적어준다.
#
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "Cocode Slack" > SLACK_TEAM_ID·SLACK_BOT_TOKEN 필드
#   ※ 두 값이 모두 있어야 인증되므로, 하나라도 못 읽으면 아무것도 주입하지 않는다(반쪽 인증 방지, DCM과 동일).
# ------------------------------------------------------------
log "8.9. SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (1Password 공용 항목 'Cocode Slack', slack MCP용)"

# 값이 빈 기존 라인은 먼저 걷어낸다 (다른 토큰과 동일 — 빈 값이 남으면 MCP가 '연결됨'처럼 보이며 호출만 실패한다)
if slack_token_line_is_empty; then
  strip_slack_token_lines
  echo "  · 값이 비어 있던 기존 SLACK_TEAM_ID/SLACK_BOT_TOKEN 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  warn "op(1Password CLI) 미설치 → SLACK_TEAM_ID·SLACK_BOT_TOKEN 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './linux-setup.sh --env-only' 실행)"
elif inject_slack_token; then
  ok "SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 완료 (~/.zshrc, 값은 커밋되지 않음)"
else
  if op_has_account; then
    warn "SLACK_TEAM_ID·SLACK_BOT_TOKEN 미주입 — 1Password에서 'Cocode Slack'의 SLACK_TEAM_ID/SLACK_BOT_TOKEN을 읽지 못했습니다."
    info "확인하세요:"
    info "  1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    info "  2) 볼트에 'Cocode Slack' 항목 + SLACK_TEAM_ID·SLACK_BOT_TOKEN 필드가 있는지"
    info "확인 후 './linux-setup.sh --env-only' 를 실행하면 값만 다시 주입됩니다 (그전까지 slack MCP는 미주입 상태)."
  else
    warn "SLACK_TEAM_ID·SLACK_BOT_TOKEN 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    info "op(1Password CLI) 설정을 마친 뒤 './linux-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
  fi
fi

# ------------------------------------------------------------
# 8.10. --env-only 마무리: 주입 결과만 요약하고 종료 (아래 10단계 전체 검증은 돌리지 않음)
#   토큰 유무는 10단계와 같은 기준(~/.zshrc의 값)으로 판단한다 — MCP의 'Connected' 표시는
#   인증 성공을 뜻하지 않기 때문 (8.5단계 주석 참고).
# ------------------------------------------------------------
if (( ENV_ONLY )); then
  log "환경변수 업데이트 결과 (--env-only)"
  ZH_VAL=$(grep '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export ZENHUB_API_TOKEN=//; s/^"//; s/"$//')
  JIRA_VAL=$(grep '^export JIRA_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export JIRA_API_TOKEN=//; s/^"//; s/"$//')
  SLANG_GPT_VAL=$(grep '^export SLANG_GPT_API_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLANG_GPT_API_KEY=//; s/^"//; s/"$//')
  # DCM은 이메일+키 두 값이 모두 있어야 인증되므로 둘 다 채워졌을 때만 '주입됨'으로 본다.
  DCM_EMAIL_VAL=$(grep '^export DCM_EMAIL=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export DCM_EMAIL=//; s/^"//; s/"$//')
  DCM_CI_KEY_VAL=$(grep '^export DCM_CI_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export DCM_CI_KEY=//; s/^"//; s/"$//')
  # slack도 DCM과 동일하게 팀 ID+봇 토큰 두 값이 모두 있어야 인증되므로 둘 다 채워졌을 때만 '주입됨'으로 본다.
  SLACK_TEAM_ID_VAL=$(grep '^export SLACK_TEAM_ID=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLACK_TEAM_ID=//; s/^"//; s/"$//')
  SLACK_BOT_TOKEN_VAL=$(grep '^export SLACK_BOT_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLACK_BOT_TOKEN=//; s/^"//; s/"$//')
  echo "  ZENHUB_API_TOKEN: $([[ -n "$ZH_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  JIRA_API_TOKEN  : $([[ -n "$JIRA_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  SLANG_GPT_API_KEY: $([[ -n "$SLANG_GPT_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  DCM_EMAIL/DCM_CI_KEY: $([[ -n "$DCM_EMAIL_VAL" && -n "$DCM_CI_KEY_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  SLACK_TEAM_ID/SLACK_BOT_TOKEN: $([[ -n "$SLACK_TEAM_ID_VAL" && -n "$SLACK_BOT_TOKEN_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo ""
  if [[ -n "$ZH_VAL" || -n "$JIRA_VAL" || -n "$SLANG_GPT_VAL" || ( -n "$DCM_EMAIL_VAL" && -n "$DCM_CI_KEY_VAL" ) || ( -n "$SLACK_TEAM_ID_VAL" && -n "$SLACK_BOT_TOKEN_VAL" ) ]]; then
    echo "✅ 완료! 새 터미널을 열거나 'source ~/.zshrc' 를 실행한 뒤 claude를 다시 켜세요."
    echo "   (jira MCP는 docker 데몬이 떠 있어야 연결됩니다 — 'docker info' 가 되는지 먼저 확인해 주세요)"
  else
    # 하나도 못 넣었으면 '완료' 배너 대신 다음 행동을 알려준다 (종료코드는 전체 설치와 같은 '경고 후 계속' 철학으로 0 유지)
    echo "⚠ 주입된 토큰이 없습니다 — 위 안내(1Password 앱 CLI 통합·금고 권한)를 마친 뒤"
    echo "   './linux-setup.sh --env-only' 를 다시 실행해 주세요."
  fi
  exit 0
fi

# ------------------------------------------------------------
# 9. 시스템 권한 — docker·kvm 그룹, 안드로이드 기기 USB 규칙
#   본체(run_system_permission_step)는 이 파일 앞부분에 정의돼 있다 — --system-only 가
#   설치 단계를 건너뛰고 이 단계만 실행할 수 있어야 하기 때문이다.
#   설치가 모두 끝난 뒤에 두는 이유: 그룹 변경은 재로그인해야 적용되므로, 안내를 설치가
#   끝난 시점에 보여줘야 사용자가 바로 로그아웃/로그인으로 이어갈 수 있다.
#   (맥의 '전체 디스크 접근 권한' 단계 자리 — 리눅스에는 그 개념이 없어 그룹·udev로 대체)
# ------------------------------------------------------------
run_system_permission_step

# ------------------------------------------------------------
# 10. 검증
# ------------------------------------------------------------
# 검증 표의 한 줄을 만든다.
#   ⚠ `cmd 2>/dev/null | head -1 || echo '❌'` 형태를 쓰면 안 된다 — 파이프라인의 종료코드는
#     마지막 head 의 것(항상 0)이라 **도구가 없어도 ❌ 가 절대 뜨지 않고 빈칸만 남는다.**
#     그래서 파이프 결과가 아니라 `have` 로 먼저 존재를 확인한다.
#   $1=명령 이름, $2=❌ 일 때 덧붙일 안내, $3.. =버전 확인 인자
ver() {
  local cmd="$1" hint="$2"; shift 2
  if have "$cmd"; then
    local out
    out="$("$cmd" "$@" </dev/null 2>&1 | head -1)"
    if [[ -n "$out" ]]; then printf '%s' "$out"; return 0; fi
  fi
  printf '%s' "❌${hint:+ $hint}"
}

log "10. 설치 검증"
# 안드로이드 관련 변수는 4-e단계가 정해 두지만, 그 단계가 실패했을 수도 있어 기본값을 채워 둔다.
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVDMANAGER="${AVDMANAGER:-$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager}"

echo "  zsh     : $(zsh --version 2>/dev/null || echo '❌ (수동 설치: sudo apt install zsh)')"
# 기본 셸은 '지금 이 터미널'이 아니라 계정 설정을 봐야 한다 (설치 중에는 여전히 bash로 실행 중이므로).
LOGIN_SHELL="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
echo "  기본 셸 : $([[ "$LOGIN_SHELL" == *zsh ]] && echo "✓ $LOGIN_SHELL (다시 로그인하면 적용)" || echo "⚠ ${LOGIN_SHELL:-알 수 없음} (수동 변경: chsh -s $(command -v zsh 2>/dev/null || echo /usr/bin/zsh))")"
echo "  git     : $(ver git '(수동 설치: sudo apt install git)' --version)"
echo "  git email: $(git config --global user.email 2>/dev/null || echo '❌ (git config --global user.email <이메일> 로 설정)')"
# GitHub 인증(gh): 3.4단계에서 1Password 토큰으로 자동 로그인을 시도한 결과 — 이게 돼 있어야
# 아래 cocode-skills·cob(co-bricks) 둘 다 설치된다.
echo "  gh(GitHub CLI): $(ver gh '(수동 설치: sudo apt install gh)' --version)"
echo "  GitHub 인증(gh): $(have gh && gh auth status >/dev/null 2>&1 \
  && echo '✓ 인증됨' \
  || echo '❌ (1Password "API Token" 볼트의 "GitHub API Token" 항목 확인 또는 gh auth login 후 재실행)')"
# docker는 '설치됨'과 '내 계정으로 쓸 수 있음'이 다르다 — 그룹에 없으면 명령마다 sudo가 필요하다.
echo "  docker  : $(ver docker '(수동 설치: 3단계 참고 — 도커 공식 저장소)' --version)"
echo "  docker 그룹: $(in_group docker && echo '✓ 가입됨' || echo '❌ 미가입 (sudo usermod -aG docker '"$(id -un)"' 후 다시 로그인 · 또는 ./linux-setup.sh --system-only)')"
echo "  kvm(에뮬레이터 가속): $([[ -e /dev/kvm ]] && { in_group kvm && echo '✓ /dev/kvm + 그룹 가입됨' || echo '⚠ /dev/kvm 은 있으나 kvm 그룹 미가입 (./linux-setup.sh --system-only)'; } || echo '❌ /dev/kvm 없음 (BIOS에서 가상화 활성화 필요 — 에뮬레이터가 매우 느립니다)')"
echo "  go      : $(ver go '(수동 설치: sudo apt install golang-go)' version)"
echo "  jq      : $(ver jq '(수동 설치: sudo apt install jq)' --version)"
echo "  direnv  : $(ver direnv '(수동 설치: sudo apt install direnv)' --version)"
echo "  java    : $(ver java '(수동 설치: sudo apt install openjdk-17-jdk)' -version)"
echo "  lefthook: $(ver lefthook '(수동 설치: 3단계 참고)' version)"
echo "  fvm     : $(ver fvm '(수동 설치: curl -fsSL https://fvm.app/install.sh | bash)' --version)"
echo "  flutter : $(ver flutter '(fvm install stable && fvm global stable)' --version)"
echo "  dart    : $(ver dart '(fvm global stable 후 새 터미널에서 확인)' --version)"
echo "  gcloud  : $(ver gcloud '(수동 설치: 4-c단계 참고)' --version)"
echo "  dcm     : $(ver dcm '(수동 설치: https://dcm.dev/docs/getting-started/)' --version)"
echo "  node    : $(ver node '(수동 설치: nvm install --lts)' --version)"
echo "  npm     : $(ver npm '(nvm 으로 Node 를 깔면 함께 들어옵니다)' --version)"
echo "  python  : $(pyenv exec python --version 2>/dev/null || python3 --version 2>/dev/null || echo '❌ (5단계 재실행 — pyenv install <버전>)')"
echo "  claude  : $(ver claude '(수동 설치: curl -fsSL https://claude.ai/install.sh | bash)' --version)"
# 다른 AI 코딩 CLI·Slack CLI — 맥(co-mac)도 같은 자리에서 셋 다 확인한다.
#   slack 은 데스크톱 앱(snap)이 같은 이름의 명령을 만들므로 `slack version` 응답으로 CLI 만 가려낸다.
echo "  codex   : $(ver codex '(수동 설치: npm install -g @openai/codex)' --version)"
echo "  agy     : $(ver agy '(수동 설치: 2.6단계 참고)' --version)"
SLACK_VER="$(have slack && slack version </dev/null 2>/dev/null | head -1 || true)"
echo "  slack(CLI): ${SLACK_VER:-❌ (수동 설치: curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash)}"
unset SLACK_VER
# 상태줄(ccstatusline / Awesome CC Statusline): npx/curl 실행형이라 have로 확인할 수 없다 —
#   ~/.claude/settings.json의 statusLine 키 등록 여부로 판정한다.
echo "  상태줄(statusline): $(grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null \
  && echo '✓ 등록됨 (Claude Code에서 적용)' \
  || echo '❌ 미등록 (수동 설정: npx -y ccstatusline@latest)')"
echo "  mcp:figma: $(claude plugin list 2>/dev/null | grep -q 'figma@claude-plugins-official' && echo '✓ 설치됨 (/mcp 로그인 필요)' || echo '❌')"
# op는 '설치됨'과 '설정됨(1Password 앱 CLI 통합)'이 다르다 — 설치만 되고 통합이 꺼져 있으면 토큰을 못 읽는다.
# 8.5단계에서 이미 판정한 OP_STATUS를 그대로 쓴다 (여기서 op를 다시 부르면 앱 승인 대기로 멈출 수 있음).
case "${OP_STATUS:-missing}" in
  ready)     echo "  op(1Password CLI): ✓ 설치 + 팀 계정 연결됨" ;;
  not-ready)
    echo "  op(1Password CLI): ⚠ 설치됨 (설정 미완료 — 토큰을 읽지 못했습니다)"
    echo "     ① 1Password 앱 > 설정(Ctrl+,) > 개발자 > '1Password CLI와 통합' 체크 확인 → './linux-setup.sh --env-only' 실행"
    echo "     ② 이미 켜져 있다면 팀 'API Token' 금고 접근 권한이 없는 경우입니다 → 팀 관리자에게 공유 요청"
    ;;
  *)         echo "  op(1Password CLI): ❌ (1단계 1password-cli 설치 확인 후 './linux-setup.sh --env-only' 실행)" ;;
esac
# 토큰 유무는 ~/.zshrc 값으로 판단한다. `claude mcp list`의 'Connected'는 서버 연결만 뜻할 뿐
# 인증 성공을 뜻하지 않는다 — 토큰이 비어도 Connected로 보이고 실제 호출만 실패한다.
ZH_VAL=$(grep '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export ZENHUB_API_TOKEN=//; s/^"//; s/"$//')
echo "  mcp:zenhub: $(claude mcp list 2>/dev/null | grep -q '^zenhub' \
  && echo "✓ 등록됨$([[ -n "$ZH_VAL" ]] && echo ' + 토큰 주입됨 (새 터미널에서 적용)' || echo ' (⚠ 토큰 미주입 — 1Password 앱 CLI 통합 후 --env-only 재실행)')" \
  || echo '❌')"
JIRA_VAL=$(grep '^export JIRA_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export JIRA_API_TOKEN=//; s/^"//; s/"$//')
echo "  mcp:mcp-atlassian(jira): $(claude mcp list 2>/dev/null | grep -q '^mcp-atlassian' \
  && echo "✓ 등록됨$([[ -n "$JIRA_VAL" ]] && echo ' + 토큰 주입됨 (새 터미널·docker 실행 중이어야 적용)' || echo ' (⚠ 토큰 미주입 — 1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')" \
  || echo '❌')"
# slang_gpt 키: MCP가 아니라 CLI가 셸 환경변수로 직접 읽는 값이라 등록 여부 없이 주입 여부만 본다.
SLANG_GPT_VAL=$(grep '^export SLANG_GPT_API_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLANG_GPT_API_KEY=//; s/^"//; s/"$//')
echo "  SLANG_GPT_API_KEY: $([[ -n "$SLANG_GPT_VAL" ]] \
  && echo '✓ 주입됨 (새 터미널에서 적용 — slang_gpt 다국어 자동 번역용)' \
  || echo '❌ 미주입 (1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')"
# DCM CI 인증 키: 이메일+키 두 값이 모두 있어야 인증되므로 둘 다 채워졌을 때만 '주입됨'으로 표시한다.
DCM_EMAIL_VAL=$(grep '^export DCM_EMAIL=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export DCM_EMAIL=//; s/^"//; s/"$//')
DCM_CI_KEY_VAL=$(grep '^export DCM_CI_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export DCM_CI_KEY=//; s/^"//; s/"$//')
echo "  DCM_EMAIL/DCM_CI_KEY: $([[ -n "$DCM_EMAIL_VAL" && -n "$DCM_CI_KEY_VAL" ]] \
  && echo '✓ 주입됨 (새 터미널에서 적용 — DCM CI 라이선스 인증용)' \
  || echo '❌ 미주입 (1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')"
# slack: MCP가 등록됐어도 SLACK_TEAM_ID·SLACK_BOT_TOKEN 둘 다 있어야 실제 호출이 된다 (DCM과 동일 기준).
SLACK_TEAM_ID_VAL=$(grep '^export SLACK_TEAM_ID=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLACK_TEAM_ID=//; s/^"//; s/"$//')
SLACK_BOT_TOKEN_VAL=$(grep '^export SLACK_BOT_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLACK_BOT_TOKEN=//; s/^"//; s/"$//')
echo "  mcp:slack: $(claude mcp list 2>/dev/null | grep -q '^slack' \
  && echo "✓ 등록됨$([[ -n "$SLACK_TEAM_ID_VAL" && -n "$SLACK_BOT_TOKEN_VAL" ]] && echo ' + 토큰 주입됨 (새 터미널에서 적용)' || echo ' (⚠ 토큰 미주입 — 1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')" \
  || echo '❌')"
# Dart 글로벌 패키지 — 본체는 4-b단계의 print_dart_packages_verification 에 있다
#   (--dart-only 마무리에서도 같은 출력을 써야 해서 함수로 뽑혀 있다)
if declare -f print_dart_packages_verification >/dev/null 2>&1; then
  print_dart_packages_verification
else
  warn "dart 글로벌 패키지 확인을 건너뜁니다 (4단계가 실행되지 않았습니다 — './linux-setup.sh --dart-only')"
fi
CS_COUNT=$(ls -d "$HOME/.claude/plugins/marketplaces/cocode-skills/plugins"/*/ 2>/dev/null | grep -c . || true)
echo "  cocode-skills: $([[ "${CS_COUNT:-0}" -gt 0 ]] && echo "✓ ${CS_COUNT}개 플러그인" || echo '❌ (위 GitHub 인증(gh) 확인 후 재실행)')"
echo "  android SDK: $([[ -x "$ANDROID_HOME/platform-tools/adb" ]] && echo "✓ $ANDROID_HOME" || echo '❌')"
echo "  adb     : $([[ -x "$ANDROID_HOME/platform-tools/adb" ]] \
  && "$ANDROID_HOME/platform-tools/adb" --version </dev/null 2>&1 | head -1 \
  || echo '❌ (4-e단계 재실행 — ~/Android/Sdk/platform-tools 에 설치됩니다)')"
echo "  sdkmanager: $([[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]] && echo '✓ 설치됨' || echo '❌')"
echo "  ndk     : $([[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME:-}" ]] && echo "✓ $ANDROID_NDK_HOME" || echo '❌')"
# AVD(안드로이드 가상 기기) 목록 — 이름만 뽑아 한 줄로 보여준다.
AVD_LIST="$("$AVDMANAGER" list avd 2>/dev/null | grep 'Name:' | sed 's/.*Name: //' | tr '\n' ' ' || true)"
echo "  avd     : $([[ -n "${AVD_LIST// /}" ]] && echo "✓ $AVD_LIST" || echo '❌ (Android Studio > Device Manager 에서 생성하거나 4-e단계 재실행)')"

echo ""
echo "✅ 완료! 다음 단계:"
echo "  1. 터미널을 새로 열거나, 로그아웃했다 다시 로그인하세요 (권장: 로그아웃/로그인)"
echo "     ↳ docker·kvm 그룹 가입과 기본 셸(zsh) 변경은 '로그인할 때' 읽히므로, 지금 열려 있는"
echo "       터미널에는 반영되지 않습니다. 다시 로그인해야 sudo 없이 docker 가 되고 프롬프트도 바뀝니다"
echo "     ↳ 지금 당장 확인만 해보려면: source ~/.zshrc (PATH·토큰) · newgrp docker (그 터미널만 docker 그룹 적용)"
echo "  2. 터미널 폰트를 'MesloLGS NF' 로 지정하세요 (7.5단계에서 자동 적용되지 않았다면)"
echo "     ↳ GNOME Terminal: 메뉴 > 기본 설정 > 프로필 > 사용자 지정 글꼴 → MesloLGS NF"
echo "     ↳ 이 폰트가 아니면 프롬프트의 아이콘·화살표가 네모(□)로 깨져 보입니다"
echo "  3. 프롬프트 모양을 취향대로 바꾸고 싶다면: p10k configure"
echo "     ↳ 팀 기본값(.p10k.zsh)이 이미 들어가 있어서 안 해도 정상 동작합니다"
echo "  4. lefthook(Git 훅)은 레포마다 한 번씩 켜야 합니다 — lefthook.yml 이 있는 프로젝트 폴더에서: lefthook install"
echo "     ↳ 이걸 해야 커밋·푸시할 때 포맷/린트/테스트가 자동으로 돌아갑니다 (설정 파일이 없는 레포에서는 할 일 없음)"
echo "  5. 1Password 연동이 안 돼 토큰이 '❌ 미주입'이라면: ./linux-setup.sh --env-only"
echo "     ↳ 1Password 앱 로그인(team-cocodeinc) → 설정(Ctrl+,) > 개발자 > '1Password CLI와 통합' 체크"
echo "       ('개발자' 탭이 없으면 설정 > 보안 > '시스템 인증으로 잠금 해제'를 먼저 켜세요)"
echo "       확인: op account list 에 팀 계정이 보이면 성공 · 그 뒤 --env-only 로 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다"
echo "     ↳ 주입 후에는 반드시 '새 터미널'에서 claude를 실행하세요 — claude는 실행 시점의 환경변수에서"
echo "       토큰을 읽으므로, 예전 터미널에서 띄운 claude는 토큰을 못 읽습니다"
echo "  6. ⚠ iOS(아이폰) 앱 빌드·배포는 리눅스에서 불가능합니다 — 애플이 맥에서만 되도록 막아 두었습니다"
echo "     ↳ 이 PC에서는 Android·Web·서버·Flutter 데스크톱(리눅스) 작업까지 가능합니다"
echo "     ↳ iOS 빌드·시뮬레이터·앱스토어 업로드가 필요하면 맥이 필요합니다 (맥 세팅: coco-de/co-mac 의 mac-setup.sh)"
echo "  7. Claude Code 로그인: claude"
echo "     ↳ 함께 설치된 다른 AI 코딩 CLI도 최초 1회 로그인이 필요합니다: codex(실행: codex) · agy(실행: agy)"
echo "     ↳ Claude Code에서 /mcp 실행 → figma를 팀 계정으로 OAuth 로그인 (최초 1회)"
echo "  8. 안드로이드 실기기로 테스트하려면 기기에서 '개발자 옵션 > USB 디버깅'을 켜고 USB로 연결하세요"
echo "     ↳ 9단계에서 넣은 USB 규칙 덕분에 sudo 없이 인식됩니다 — 'adb devices' 로 확인"
echo "     ↳ 'no permissions' 로 뜨면 다시 로그인했는지 확인하고, 그래도 안 되면: ./linux-setup.sh --system-only"
echo "  9. GitHub 인증(gh)이 '❌'이면 cocode-skills·cob(co-bricks) 둘 다 설치되지 않습니다 (3.4단계에서 시도)"
echo "     ↳ 팀 'API Token' 볼트 > 'GitHub API Token' > 'credential' 필드에서 읽어 자동 로그인합니다"
echo "     ↳ 그래도 안 되면 수동으로: gh auth login 후 스크립트 재실행"
echo "       (cob만 다시 깔면 되는 상황이면 './linux-setup.sh --dart-only' 가 더 빠릅니다)"
