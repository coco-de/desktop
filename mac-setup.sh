#!/bin/bash
# ============================================================
# 맥 초기 개발환경 세팅 스크립트
# 전제: Homebrew, Xcode 설치 완료
# 실행: chmod +x mac-setup.sh && ./mac-setup.sh
#
# 기존 맥의 테마/설정을 그대로 가져오려면, 기존 맥에서
#   ~/.zshrc, ~/.p10k.zsh
# 를 이 스크립트와 같은 폴더에 복사해 두세요. (있으면 그대로 사용)
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Homebrew 경로 (Apple Silicon / Intel 자동 감지)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  echo "❌ Homebrew가 없습니다. 먼저 설치하세요: https://brew.sh"
  exit 1
fi

log()  { echo ""; echo "▶ $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 모든 y/n 확인 프롬프트 자동 통과
export NONINTERACTIVE=1          # Homebrew 비대화 모드
export CI=true                   # 많은 CLI가 CI 모드에서 프롬프트 생략

# ------------------------------------------------------------
# 1. GUI 앱 (brew cask)
# ------------------------------------------------------------
log "GUI 앱 설치 (Android Studio, Slack, Figma, Superset, Claude Desktop, Chrome, Dia, 1Password, Tailscale, Orca, Lumide, Zed)"

# cask 설치 (이미 /Applications 에 수동 설치된 앱은 건너뜀)
install_cask() {
  # $1: cask 토큰 (brew list/skip 판별용), $2: 앱 이름, $3: 설치 인자(탭 경로 등, 기본값 $1)
  local cask="$1" app="$2" install_target="${3:-$1}"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "  ✓ $cask 이미 설치됨 (brew)"
  elif [[ -n "$app" && ( -d "/Applications/$app" || -d "$HOME/Applications/$app" ) ]]; then
    echo "  ✓ $app 이미 존재 → 건너뜀"
  else
    brew install --cask "$install_target" || echo "  ⚠ $cask 설치 실패 → 건너뜀 (수동 확인 필요)"
  fi
}

install_cask android-studio         "Android Studio.app"
install_cask slack                  "Slack.app"
install_cask figma                  "Figma.app"
install_cask superset               "Superset.app"
install_cask claude                 "Claude.app"
install_cask google-chrome          "Google Chrome.app"
install_cask thebrowsercompany-dia  "Dia.app"
install_cask 1password              "1Password.app"
install_cask 1password-cli          ""                          # op CLI (ZENHUB_API_TOKEN 공용 토큰 주입에 사용)
install_cask tailscale              "Tailscale.app"
install_cask orca                   "Orca.app"                 stablyai/orca/orca
install_cask lumide                 "Lumide.app"
install_cask zed                    "Zed.app"

# ------------------------------------------------------------
# 2. Claude Code CLI
# ------------------------------------------------------------
log "Claude Code CLI 설치"
if brew list --cask claude-code >/dev/null 2>&1 || have claude; then
  echo "  ✓ claude-code 이미 설치됨"
else
  brew install --cask claude-code || echo "  ⚠ claude-code 설치 실패 → 건너뜀"
fi

# ------------------------------------------------------------
# 2.5. Claude Code MCP 서버 / 플러그인 (jira, figma, zenhub, maestro, flutter-mcp-toolkit)
#   MCP는 3계층으로 설치된다:
#     ① 플러그인 계층  : claude plugin install (jira=atlassian, figma, flutter-mcp-toolkit) — 아래에서 자동
#     ② 로컬 바이너리   : maestro CLI·flutter-mcp-toolkit CLI(아래), marionette_mcp·dart mcp-server(4단계에서 설치)
#     ③ 인증 계층      : atlassian/figma OAuth는 최초 1회 `/mcp`에서 수동 로그인 (자동화 불가),
#                        zenhub은 ~/.zshrc의 ZENHUB_API_TOKEN(런타임 확장)로 인증 — 토큰 값은 커밋 금지,
#                        flutter-mcp-toolkit은 별도 인증 불필요
#   ※ marionette·dart·figma(serve) MCP 정의는 사설 cocode-skills 플러그인 번들에서 제공됨
#     (coco-de/skills의 install.sh — 아래 3.5단계에서 설치)
# ------------------------------------------------------------
log "Claude Code MCP 설치 (jira=atlassian, figma 플러그인 + zenhub 등록 + maestro CLI + flutter-mcp-toolkit)"

if have claude; then
  # 공식 마켓플레이스 등록 (이미 있으면 무시)
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 || true

  # 원격 OAuth 플러그인: 설치는 자동, 로그인은 최초 1회 `/mcp`에서 수동
  for p in atlassian figma; do
    if claude plugin list 2>/dev/null | grep -q "${p}@claude-plugins-official"; then
      echo "  ✓ ${p} 플러그인 이미 설치됨"
    else
      claude plugin install "${p}@claude-plugins-official" --scope user >/dev/null 2>&1 \
        && echo "  ✓ ${p} 플러그인 설치 (최초 1회 /mcp 로그인 필요)" \
        || echo "  ⚠ ${p} 플러그인 설치 실패 → 건너뜀 (claude 로그인 후 재시도)"
    fi
  done

  # zenhub MCP (사설 cocode-skills 루트 .mcp.json과 동일 구조 — 원격 서버 + API 토큰)
  #   토큰은 ~/.zshrc의 ZENHUB_API_TOKEN에서 런타임 확장되므로 단일따옴표로 리터럴 등록 (토큰 값 커밋 금지)
  if claude mcp list 2>/dev/null | grep -q "^zenhub"; then
    echo "  ✓ zenhub MCP 이미 등록됨"
  else
    claude mcp add zenhub --scope user -- \
      npx -y mcp-remote https://api.zenhub.com/mcp \
      --header 'Authorization:${ZENHUB_API_TOKEN}' \
      --header 'X-zh-workspace:69ae742925c359000f5acf14' >/dev/null 2>&1 \
      && echo "  ✓ zenhub MCP 등록 (토큰은 8.5단계에서 1Password 공용 항목으로 주입)" \
      || echo "  ⚠ zenhub MCP 등록 실패 → 건너뜀"
  fi
else
  echo "  ⚠ claude CLI가 없어 MCP 플러그인 설치를 건너뜁니다"
fi

# maestro CLI: pixel-loop의 maestro MCP가 요구 (미설치 시 MCP 연결 실패)
if have maestro; then
  echo "  ✓ maestro 이미 설치됨"
else
  curl -Ls https://get.maestro.mobile.dev | bash \
    && echo "  ✓ maestro 설치 완료" \
    || echo "  ⚠ maestro 설치 실패 → 건너뜀 (https://maestro.mobile.dev 수동 설치)"
fi
# marionette_mcp / dart mcp-server 는 4단계(Dart 글로벌 패키지 / FVM)에서 설치됨

# flutter-mcp-toolkit (mcp_flutter): 실행 중인 Flutter 앱을 AI 에이전트가 검사/조작하는 MCP 서버
#   ① 로컬 바이너리(CLI): 공식 install.sh
#   ② Claude Code 플러그인: 마켓플레이스 등록 + 유저 스코프 설치 (jira/figma와 동일 패턴)
#   ※ 앱별 연동(`flutter-mcp-toolkit codegen-init`으로 mcp_toolkit 패키지 추가)은 각 Flutter 프로젝트에서 별도 진행 (이 스크립트 범위 밖)
if have flutter-mcp-toolkit; then
  echo "  ✓ flutter-mcp-toolkit 이미 설치됨"
else
  curl -fsSL https://raw.githubusercontent.com/Arenukvern/mcp_flutter/main/install.sh | bash \
    && echo "  ✓ flutter-mcp-toolkit 설치 완료" \
    || echo "  ⚠ flutter-mcp-toolkit 설치 실패 → 건너뜀 (https://github.com/Arenukvern/mcp_flutter 수동 설치)"
fi

if have claude; then
  claude plugin marketplace add Arenukvern/mcp_flutter >/dev/null 2>&1 || true
  if claude plugin list 2>/dev/null | grep -q "flutter-mcp-toolkit@Arenukvern-mcp_flutter"; then
    echo "  ✓ flutter-mcp-toolkit 플러그인 이미 설치됨"
  else
    claude plugin install "flutter-mcp-toolkit@Arenukvern-mcp_flutter" --scope user >/dev/null 2>&1 \
      && echo "  ✓ flutter-mcp-toolkit 플러그인 설치 완료" \
      || echo "  ⚠ flutter-mcp-toolkit 플러그인 설치 실패 → 건너뜀 (claude 로그인 후 재시도)"
  fi
else
  echo "  ⚠ claude CLI가 없어 flutter-mcp-toolkit 플러그인 설치를 건너뜁니다"
fi

# ------------------------------------------------------------
# 3. CLI 도구 (go, pyenv, nvm, git 등)
# ------------------------------------------------------------
log "CLI 도구 설치 (go, pyenv, nvm, git, cocoapods 등)"
# zsh-syntax-highlighting, direnv, openjdk@17: 기존 .zshrc에서 참조하는 도구들
FORMULAE=(go pyenv nvm git gh jq cocoapods fastlane awscli colima docker docker-compose zsh-syntax-highlighting direnv openjdk@17)
for f in "${FORMULAE[@]}"; do
  brew list "$f" >/dev/null 2>&1 && echo "  ✓ $f 이미 설치됨" || brew install "$f"
done

# ------------------------------------------------------------
# 3.2. Git 전역 사용자 이메일 설정 (커밋 작성자 정보)
#   커밋에 기록될 회사 이메일을 입력받아 git config --global user.email에 저장한다.
#   이미 설정돼 있으면 그대로 두고 건너뜀(멱등).
#   파이프 실행(TTY 없음)이면 멈추지 않고 건너뜀(재실행 시 입력 가능).
# ------------------------------------------------------------
log "Git 사용자 이메일 설정 (git config --global user.email)"
GIT_EMAIL_CURRENT="$(git config --global user.email 2>/dev/null || true)"
if [[ -n "$GIT_EMAIL_CURRENT" ]]; then
  echo "  ✓ 이미 설정됨 ($GIT_EMAIL_CURRENT)"
elif [[ -t 0 ]]; then
  while true; do
    printf "  ✉️  커밋에 사용할 회사 이메일을 입력하세요 (예: cody@cocode.im) · 건너뛰려면 s 입력 후 Enter: "
    read -r git_email || git_email="s"
    if [[ "$git_email" == "s" || "$git_email" == "S" ]]; then
      echo "  ⚠ Git 이메일 설정 건너뜀 → 나중에 직접 실행: git config --global user.email <이메일>"
      break
    fi
    if [[ "$git_email" == *@* ]]; then
      git config --global user.email "$git_email"
      echo "  ✓ user.email 설정 완료 ($git_email)"
      break
    fi
    echo "  ✗ 이메일 형식이 아닙니다(@가 없음) — 다시 입력해 주세요."
  done
else
  echo "  ⚠ 비대화형 실행 → Git 이메일 설정 건너뜀. 직접 실행: git config --global user.email <이메일>"
fi

# ------------------------------------------------------------
# 3.5. cocode-skills 팀 플러그인 설치 (사설 레포 coco-de/skills)
#   marionette·dart·figma(serve)·maestro·dev-cycle·coui 등 cc-* 플러그인 번들을 설치한다.
#   private 레포라 `claude plugin marketplace add`가 안 되므로 팀 install.sh로 동기화.
#   전제: gh 인증(gh auth login) + jq(위 3단계에서 설치). rsync는 macOS 기본 제공.
# ------------------------------------------------------------
log "cocode-skills 팀 플러그인 설치 (coco-de/skills install.sh)"
if have gh && gh auth status >/dev/null 2>&1; then
  cs_installer="$(mktemp)"
  if gh api repos/coco-de/skills/contents/install.sh --jq '.content' 2>/dev/null \
       | base64 -d > "$cs_installer" && [[ -s "$cs_installer" ]]; then
    bash "$cs_installer" \
      && echo "  ✓ cocode-skills 팀 플러그인 설치 완료" \
      || echo "  ⚠ cocode-skills 설치 실패 → 건너뜀 (재시도: bash <(gh api repos/coco-de/skills/contents/install.sh --jq '.content' | base64 -d))"
  else
    echo "  ⚠ install.sh를 받지 못했습니다 (coco-de/skills 접근 권한 확인) → 건너뜀"
  fi
  rm -f "$cs_installer"
else
  echo "  ⚠ gh 인증 필요 → 'gh auth login' 후 재실행하면 cocode-skills 팀 플러그인이 설치됩니다"
fi

# ------------------------------------------------------------
# 4. FVM + Flutter stable 글로벌 설치
# ------------------------------------------------------------
log "FVM 설치 및 Flutter stable 글로벌 설정"
# 최신 Homebrew는 서드파티 tap을 신뢰 등록(brew trust)해야 설치를 허용한다.
# (brew trust 명령이 없는 구버전 Homebrew에서는 그냥 건너뜀)
brew tap leoafarias/fvm 2>/dev/null || true
brew trust leoafarias/fvm 2>/dev/null || true
brew list fvm >/dev/null 2>&1 && echo "  ✓ fvm 이미 설치됨" || brew install fvm
yes | fvm install stable
yes | fvm global stable --force 2>/dev/null || yes | fvm global stable
export PATH="$HOME/fvm/default/bin:$PATH"

# Dart 글로벌 패키지 (serverpod_cli, marionette_mcp, mcp_server_dart)
log "Dart 글로벌 패키지 설치"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PUB_CACHE/bin:$PATH"
dart pub global activate serverpod_cli 4.0.0-beta.0 || echo "  ⚠ serverpod_cli 설치 실패 → 건너뜀"
dart pub global activate marionette_mcp || echo "  ⚠ marionette_mcp 설치 실패 → 건너뜀"
dart pub global activate mcp_server_dart || echo "  ⚠ mcp_server_dart 설치 실패 → 건너뜀"

# Google Cloud CLI (gcloud)
log "Google Cloud CLI 설치"
if have gcloud; then
  echo "  ✓ gcloud 이미 설치됨"
else
  brew install --cask gcloud-cli 2>/dev/null || brew install --cask google-cloud-sdk || echo "  ⚠ gcloud 설치 실패 → 건너뜀"
fi

# DCM (Dart Code Metrics)
log "DCM 설치"
# 서드파티 tap 신뢰 등록 — 없으면 최신 Homebrew가 "untrusted tap" 에러로 설치를 거부한다
brew tap CQLabs/dcm 2>/dev/null || true
brew trust CQLabs/dcm 2>/dev/null || true
brew list dcm >/dev/null 2>&1 && echo "  ✓ dcm 이미 설치됨" || yes | brew install dcm || echo "  ⚠ dcm 설치 실패 → 건너뜀"

# Android SDK 구성요소 (cmdline-tools, platform-tools, build-tools, platforms, NDK, 에뮬레이터, AVD)
# Android Studio(GUI)를 직접 실행해 SDK 설치 마법사를 거치지 않아도 되도록,
# brew의 cmdline-tools만으로 표준 SDK 위치($ANDROID_HOME)에 필요한 구성요소를 전부 설치한다.
log "Android SDK 구성요소 설치 (cmdline-tools, platform-tools, build-tools, platforms, NDK, AVD)"

export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
mkdir -p "$ANDROID_HOME"

# sdkmanager 실행에는 JDK가 필요 (openjdk@17은 위 3단계에서 설치됨)
JAVA_HOME="$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

brew list --cask android-commandlinetools >/dev/null 2>&1 && echo "  ✓ android-commandlinetools 이미 설치됨" || \
  brew install --cask android-commandlinetools || echo "  ⚠ android-commandlinetools 설치 실패 → 건너뜀"

# brew의 cmdline-tools는 구버전인 데다, avdmanager가 심볼릭 링크를 끝까지 따라가 brew 설치
# 경로를 SDK 루트로 인식하기 때문에 $ANDROID_HOME에 설치한 시스템 이미지를 찾지 못한다
# (AVD 생성이 "Package path is not valid"로 실패하던 원인).
# 그래서 brew 것은 부트스트랩으로만 쓰고, 최신 cmdline-tools를 $ANDROID_HOME 안에 정식 설치한다.
BREW_SDKMANAGER="$(brew --prefix)/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager"
# 이전 버전 스크립트가 만들어 둔 심볼릭 링크가 있으면 정식 설치를 위해 제거
[[ -L "$ANDROID_HOME/cmdline-tools/latest" ]] && rm "$ANDROID_HOME/cmdline-tools/latest"
if [[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "  ✓ cmdline-tools 이미 설치됨 ($ANDROID_HOME/cmdline-tools/latest)"
elif [[ -x "$BREW_SDKMANAGER" ]]; then
  yes | "$BREW_SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
  yes | "$BREW_SDKMANAGER" --sdk_root="$ANDROID_HOME" "cmdline-tools;latest" \
    || echo "  ⚠ cmdline-tools 설치 실패 → 건너뜀"
fi

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
# 정식 설치가 실패했다면 brew 버전으로라도 SDK 구성요소 설치는 계속 진행
if [[ ! -x "$SDKMANAGER" && -x "$BREW_SDKMANAGER" ]]; then
  SDKMANAGER="$BREW_SDKMANAGER"
  AVDMANAGER="$(dirname "$BREW_SDKMANAGER")/avdmanager"
fi

if [[ -x "$SDKMANAGER" ]]; then
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

  # 최신 안정 버전 자동 탐지 (프리뷰 채널 제외) — pyenv 최신 버전 탐지와 동일한 방식
  SDK_LIST="$("$SDKMANAGER" --sdk_root="$ANDROID_HOME" --list 2>/dev/null)" || true
  LATEST_PLATFORM=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*platforms;android-[0-9]+' | tr -d ' ' | sort -t'-' -k2 -n | tail -1)
  LATEST_BUILD_TOOLS=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*build-tools;[0-9]+\.[0-9]+\.[0-9]+' | tr -d ' ' | sort -t';' -k2 -V | tail -1)

  # NDK는 sdkmanager 목록의 '최신'이 아니라 Flutter가 요구하는 버전으로 고정한다.
  # (목록 최신값은 r30-beta 같은 프리뷰라 Flutter stable 빌드의 android.ndkVersion과 어긋나
  #  Gradle NDK 불일치를 유발한다. Flutter SDK에 박힌 핀 값을 그대로 사용한다.)
  FLUTTER_ROOT="$(cd "$(dirname "$(command -v flutter 2>/dev/null)")/.." 2>/dev/null && pwd)"
  FLUTTER_NDK="$(grep -oE "ndkVersion = '[0-9.]+'" "$FLUTTER_ROOT/packages/flutter_tools/lib/src/android/gradle_utils.dart" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [[ -n "$FLUTTER_NDK" ]]; then
    LATEST_NDK="ndk;$FLUTTER_NDK"
    echo "  · NDK: Flutter 요구 버전 사용 → $LATEST_NDK"
  else
    LATEST_NDK="ndk;28.2.13676358"
    echo "  ⚠ Flutter NDK 핀을 못 읽어 기본값 사용: $LATEST_NDK"
  fi

  ARCH_ABI="arm64-v8a"
  [[ "$(uname -m)" == "x86_64" ]] && ARCH_ABI="x86_64"
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
      || echo "  ⚠ $PKG 설치 실패 → 건너뜀"
  done

  # ANDROID_NDK_HOME은 실제 설치된 디스크 경로 기준으로 잡는다 (요구 버전 우선, 없으면 설치된 것 사용)
  WANT_NDK="${LATEST_NDK#ndk;}"
  if [[ -d "$ANDROID_HOME/ndk/$WANT_NDK" ]]; then
    export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$WANT_NDK"
  elif ls -d "$ANDROID_HOME"/ndk/*/ >/dev/null 2>&1; then
    ANDROID_NDK_HOME="$(ls -d "$ANDROID_HOME"/ndk/*/ | sort -V | tail -1)"
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME%/}"
  fi

  # AVD 생성 (이미 있으면 건너뜀) — 이름은 실제 설치한 시스템 이미지의 API 버전을 따른다
  if [[ -x "$AVDMANAGER" && -n "$SYSTEM_IMAGE" ]]; then
    AVD_NAME="Pixel_6_API_${IMAGE_API}"
    if "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD_NAME"; then
      echo "  ✓ AVD($AVD_NAME) 이미 존재"
    else
      echo "no" | "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_6 \
        || echo "  ⚠ AVD 생성 실패 → 건너뜀 (Android Studio Device Manager에서 수동 생성 가능)"
    fi
  elif [[ -x "$AVDMANAGER" ]]; then
    echo "  ⚠ ${ARCH_ABI}용 google_apis 시스템 이미지를 찾지 못해 AVD 생성을 건너뜁니다"
  fi
else
  echo "  ⚠ sdkmanager를 찾을 수 없어 Android SDK 구성요소 설치를 건너뜁니다"
fi

# ------------------------------------------------------------
# 5. Python (pyenv로 최신 3.x)
# ------------------------------------------------------------
log "Python 최신 3.x 설치 (pyenv)"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true
LATEST_PY=$(pyenv install --list | grep -E '^\s*3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
pyenv versions --bare | grep -qx "$LATEST_PY" && echo "  ✓ Python $LATEST_PY 이미 설치됨" || pyenv install "$LATEST_PY"
pyenv global "$LATEST_PY"

# ------------------------------------------------------------
# 6. Node.js (nvm으로 LTS, npm 포함)
# ------------------------------------------------------------
log "Node.js LTS 설치 (nvm, npm 포함)"
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
# shellcheck disable=SC1091
source "$(brew --prefix nvm)/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

# ------------------------------------------------------------
# 7. oh-my-zsh + powerlevel10k + 플러그인
# ------------------------------------------------------------
log "oh-my-zsh 설치"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "  ✓ oh-my-zsh 이미 설치됨"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

log "powerlevel10k + 플러그인 설치"
[[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] || \
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
# 기존 .zshrc가 ~/powerlevel10k 를 직접 source 하므로 동일 경로에도 clone
[[ -d "$HOME/powerlevel10k" ]] || \
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k"

# p10k 권장 폰트 (MesloLGS NF)
brew install --cask font-meslo-lg-nerd-font 2>/dev/null || true

# ------------------------------------------------------------
# 8. ~/.zshrc / ~/.p10k.zsh 반영
#    - 스크립트 옆에 기존 맥의 .zshrc/.p10k.zsh가 있으면 그대로 복사
#    - 없으면 아래 기본 설정 생성
# ------------------------------------------------------------
log "~/.zshrc 설정"

if [[ -f "$SCRIPT_DIR/.p10k.zsh" ]]; then
  cp "$SCRIPT_DIR/.p10k.zsh" "$HOME/.p10k.zsh"
  echo "  ✓ 기존 .p10k.zsh 복사 완료"
elif [[ ! -f "$HOME/.p10k.zsh" ]]; then
  # 기존 맥에서 .p10k.zsh를 가져오지 않은 새 맥: powerlevel10k 기본 설정을 복사한다.
  # 이게 없으면 새 셸마다 설정 마법사(p10k configure)가 떠서 "세팅이 정상적이지 않게" 보인다.
  P10K_DEFAULT="$ZSH_CUSTOM/themes/powerlevel10k/config/p10k-lean.zsh"
  if [[ -f "$P10K_DEFAULT" ]]; then
    cp "$P10K_DEFAULT" "$HOME/.p10k.zsh"
    echo "  ✓ 기본 .p10k.zsh 생성 완료 (p10k-lean, 설정 마법사 생략)"
  else
    echo "  ⚠ p10k 기본 설정 템플릿을 찾지 못함 — 새 셸에서 'p10k configure' 직접 실행 필요"
  fi
fi

if [[ -f "$SCRIPT_DIR/.zshrc" ]]; then
  [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
  cp "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
  # --- 새 맥 호환 패치 ---
  # JAVA_HOME: 버전 하드코딩 경로 → brew 심볼릭 경로로 교체
  sed -i '' 's|^export JAVA_HOME=.*openjdk@17.*|export JAVA_HOME="$(/opt/homebrew/bin/brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"|' "$HOME/.zshrc"
  # 미설치 도구를 무조건 source 하는 라인 → 파일 존재 시에만 source 하도록 가드
  sed -i '' 's|^\. "\$HOME/.local/bin/env"|[[ -f "$HOME/.local/bin/env" ]] \&\& . "$HOME/.local/bin/env"|' "$HOME/.zshrc"
  sed -i '' 's|^eval "\$(direnv hook zsh)"|command -v direnv >/dev/null \&\& eval "$(direnv hook zsh)"|' "$HOME/.zshrc"
  echo "  ✓ 기존 .zshrc 복사 완료 (기존 파일은 백업됨, 새 맥 호환 패치 적용)"
else
  [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
  cat > "$HOME/.zshrc" <<'ZSHRC'
# ===== Powerlevel10k instant prompt =====
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===== Homebrew =====
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ===== oh-my-zsh =====
export ZSH="$HOME/.oh-my-zsh"
# ~/.p10k.zsh 가 없더라도 설정 마법사가 자동으로 뜨지 않게 한다(정상 프롬프트로 시작).
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# ===== FVM / Flutter =====
export PATH="$HOME/fvm/default/bin:$PATH"

# ===== Go =====
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# ===== Python (pyenv) =====
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# ===== Node (nvm) =====
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix nvm)/nvm.sh" ] && source "$(brew --prefix nvm)/nvm.sh"
[ -s "$(brew --prefix nvm)/etc/bash_completion.d/nvm" ] && source "$(brew --prefix nvm)/etc/bash_completion.d/nvm"

# ===== Android =====
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# ===== powerlevel10k config =====
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
ZSHRC
  echo "  ✓ 기본 .zshrc 생성 완료 (기존 파일은 백업됨)"
fi

# ------------------------------------------------------------
# 8.5. ZENHUB_API_TOKEN 주입 (팀 공용 토큰 — 1Password에서 자동 주입)
#   토큰 값은 git에 커밋하지 않는다. 팀 공용 1Password 항목에서 op CLI로 읽어
#   ~/.zshrc의 ZENHUB_API_TOKEN에 기록한다. (section 8에서 .zshrc가 확정된 뒤 실행)
#   전제: op(1password-cli) 설치됨 + 1Password 앱 CLI 통합 활성화(팀 team-cocodeinc 계정 로그인)
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "ZenHub API Token" > credential 필드
#     (계정이 여러 개인 사용자도 동작하도록 --account로 팀 계정을 명시)
#   ※ op 준비가 안 됐고 터미널(TTY)이면 여기서 멈춰 안내 → 1Password 설정 완료 후 Enter로 재시도.
#     파이프 실행(TTY 없음)이면 멈추지 않고 건너뜀(재실행 시 자동 주입).
# ------------------------------------------------------------
ZENHUB_TOKEN_OP_ACCOUNT="team-cocodeinc.1password.com"                # 팀 1Password 계정 (비밀 아님)
ZENHUB_TOKEN_OP_REF="op://API Token/ZenHub API Token/credential"      # 팀 공용 항목 경로 (값은 1Password에만 존재)

# op read → ~/.zshrc의 ZENHUB_API_TOKEN 주입. 성공 시 0, 실패 시 1 반환.
inject_zenhub_token() {
  local tok
  tok="$(op read --account "$ZENHUB_TOKEN_OP_ACCOUNT" "$ZENHUB_TOKEN_OP_REF" 2>/dev/null)" || return 1
  [[ -n "$tok" ]] || return 1
  touch "$HOME/.zshrc"
  # 기존 ZENHUB_API_TOKEN 라인 제거 후 재기록 (sed 치환 시 토큰 특수문자 문제 회피)
  { grep -v '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" || true; } > "$HOME/.zshrc.tmp"
  mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
  printf 'export ZENHUB_API_TOKEN=%q\n' "$tok" >> "$HOME/.zshrc"
}

log "ZENHUB_API_TOKEN 주입 (1Password 공용 토큰)"
if ! have op; then
  echo "  ⚠ op(1password-cli) 미설치 → ZENHUB_API_TOKEN 수동 설정 필요"
elif inject_zenhub_token; then
  echo "  ✓ ZENHUB_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
elif [[ -t 0 ]]; then
  # 대화형: 1Password 로그인 + CLI 통합을 마칠 때까지 멈춰서 안내 → Enter로 재시도
  while true; do
    echo ""
    echo "  ⏸  ZenHub 토큰 주입에 1Password 설정이 필요합니다. 아래를 완료해 주세요:"
    echo "       1) 1Password 앱을 열고 팀 계정($ZENHUB_TOKEN_OP_ACCOUNT)으로 로그인"
    echo "       2) 앱 > 설정(⌘,) > 개발자 > '1Password CLI와 통합' 체크"
    echo "          (이 항목이 안 보이면: 설정 > 보안 > 'Touch ID로 잠금 해제'를 먼저 켜세요)"
    echo ""
    printf "     완료했으면 Enter(재시도) · 나중에 하려면 s 입력 후 Enter: "
    read -r zh_ans || zh_ans="s"
    if [[ "$zh_ans" == "s" || "$zh_ans" == "S" ]]; then
      echo "  ⚠ ZENHUB_API_TOKEN 주입 건너뜀 → 나중에 스크립트를 재실행하면 자동 주입됩니다"
      break
    fi
    if inject_zenhub_token; then
      echo "  ✓ ZENHUB_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
      break
    fi
    echo "  ✗ 아직 op read 실패 — 1Password 로그인/CLI 통합 상태를 확인한 뒤 다시 Enter를 누르세요."
  done
else
  # 비대화형(TTY 없음): 멈추지 않고 건너뜀
  echo "  ⚠ op read 실패(비대화형) → 1Password 앱 CLI 통합 후 스크립트 재실행 시 자동 주입"
fi

# ------------------------------------------------------------
# 9. 검증
# ------------------------------------------------------------
log "설치 검증"
echo "  fvm     : $(fvm --version 2>/dev/null || echo '❌')"
echo "  flutter : $(flutter --version 2>/dev/null | head -1 || echo '❌')"
echo "  go      : $(go version 2>/dev/null || echo '❌')"
echo "  python  : $(pyenv exec python --version 2>/dev/null || echo '❌')"
echo "  node    : $(node --version 2>/dev/null || echo '❌')"
echo "  npm     : $(npm --version 2>/dev/null || echo '❌')"
echo "  claude  : $(claude --version 2>/dev/null || echo '설치됨 (새 터미널에서 확인)')"
echo "  git email: $(git config --global user.email 2>/dev/null || echo '❌ (git config --global user.email <이메일> 로 설정)')"
echo "  mcp:jira: $(claude plugin list 2>/dev/null | grep -q 'atlassian@claude-plugins-official' && echo '✓ 설치됨 (/mcp 로그인 필요)' || echo '❌')"
echo "  mcp:figma: $(claude plugin list 2>/dev/null | grep -q 'figma@claude-plugins-official' && echo '✓ 설치됨 (/mcp 로그인 필요)' || echo '❌')"
ZH_VAL=$(grep '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export ZENHUB_API_TOKEN=//; s/^"//; s/"$//')
echo "  mcp:zenhub: $(claude mcp list 2>/dev/null | grep -q '^zenhub' && echo "✓ 등록됨$([[ -z "$ZH_VAL" ]] && echo ' (⚠ 토큰 미주입 — op signin 후 재실행)')" || echo '❌')"
echo "  maestro : $(maestro --version 2>/dev/null | head -1 || echo '❌')"
echo "  marionette: $([[ -x "$PUB_CACHE/bin/marionette_mcp" ]] && echo '✓' || echo '❌')"
echo "  mcp_server_dart: $(dart pub global list 2>/dev/null | grep -q '^mcp_server_dart ' && echo '✓' || echo '❌')"
echo "  mcp:flutter-mcp-toolkit: $(have flutter-mcp-toolkit && echo -n '✓ CLI ' || echo -n '❌ CLI '; claude plugin list 2>/dev/null | grep -q 'flutter-mcp-toolkit@Arenukvern-mcp_flutter' && echo '+ ✓ 플러그인' || echo '+ ❌ 플러그인')"
CS_COUNT=$(ls -d "$HOME/.claude/plugins/marketplaces/cocode-skills/plugins"/*/ 2>/dev/null | grep -c .)
echo "  cocode-skills: $([[ "$CS_COUNT" -gt 0 ]] && echo "✓ ${CS_COUNT}개 플러그인" || echo '❌ (gh auth login 후 재실행)')"
echo "  android : $([[ -x "$ANDROID_HOME/platform-tools/adb" ]] && echo "✓ $ANDROID_HOME" || echo '❌')"
echo "  ndk     : $([[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME:-}" ]] && echo "✓ $ANDROID_NDK_HOME" || echo '❌')"
echo "  avd     : $([[ -n "${AVD_NAME:-}" ]] && "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD_NAME" && echo "✓ $AVD_NAME" || echo '❌')"

echo ""
echo "✅ 완료! 다음 단계:"
echo "  1. 새 터미널을 열거나: source ~/.zshrc"
echo "  2. p10k 테마 설정이 없다면: p10k configure"
echo "  3. Android Studio 실행 후 flutter doctor (SDK/NDK/AVD는 이미 자동 설치·구성됨)"
echo "  4. Claude Code 로그인: claude"
echo "  5. Claude Code에서 /mcp 실행 → atlassian(jira), figma 각각 팀 계정으로 OAuth 로그인 (최초 1회)"
echo "  6. zenhub 토큰: 실행 중 8.5단계에서 1Password 설정 안내가 나오면(앱 로그인 + 설정>개발자>'1Password CLI와 통합' 체크) 완료 후 Enter로 자동 주입 (건너뛰었다면 스크립트 재실행 시 주입)"
echo "  7. cocode-skills 팀 플러그인이 '❌'이면: gh auth login 후 스크립트 재실행 (사설 레포 접근에 gh 인증 필요)"
echo "  8. flutter-mcp-toolkit을 특정 Flutter 프로젝트에서 쓰려면 해당 프로젝트에서: flutter-mcp-toolkit codegen-init (mcp_toolkit 패키지 추가, 앱별 1회)"
