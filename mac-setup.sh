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
log "GUI 앱 설치 (Android Studio, Slack, Figma, Superset, Claude Desktop, Chrome, Dia, 1Password, Tailscale)"

# cask 설치 (이미 /Applications 에 수동 설치된 앱은 건너뜀)
install_cask() {
  local cask="$1" app="$2"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "  ✓ $cask 이미 설치됨 (brew)"
  elif [[ -n "$app" && ( -d "/Applications/$app" || -d "$HOME/Applications/$app" ) ]]; then
    echo "  ✓ $app 이미 존재 → 건너뜀"
  else
    brew install --cask "$cask" || echo "  ⚠ $cask 설치 실패 → 건너뜀 (수동 확인 필요)"
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
install_cask tailscale              "Tailscale.app"

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
# 3. CLI 도구 (go, pyenv, nvm, git 등)
# ------------------------------------------------------------
log "CLI 도구 설치 (go, pyenv, nvm, git, cocoapods 등)"
# zsh-syntax-highlighting, direnv, openjdk@17: 기존 .zshrc에서 참조하는 도구들
FORMULAE=(go pyenv nvm git gh cocoapods fastlane awscli colima docker docker-compose zsh-syntax-highlighting direnv openjdk@17)
for f in "${FORMULAE[@]}"; do
  brew list "$f" >/dev/null 2>&1 && echo "  ✓ $f 이미 설치됨" || brew install "$f"
done

# ------------------------------------------------------------
# 4. FVM + Flutter stable 글로벌 설치
# ------------------------------------------------------------
log "FVM 설치 및 Flutter stable 글로벌 설정"
brew tap leoafarias/fvm 2>/dev/null || true
brew list fvm >/dev/null 2>&1 && echo "  ✓ fvm 이미 설치됨" || brew install fvm
yes | fvm install stable
yes | fvm global stable --force 2>/dev/null || yes | fvm global stable
export PATH="$HOME/fvm/default/bin:$PATH"

# Dart 글로벌 패키지 (serverpod_cli, marionette_mcp)
log "Dart 글로벌 패키지 설치"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PUB_CACHE/bin:$PATH"
dart pub global activate serverpod_cli 4.0.0-beta.0 || echo "  ⚠ serverpod_cli 설치 실패 → 건너뜀"
dart pub global activate marionette_mcp || echo "  ⚠ marionette_mcp 설치 실패 → 건너뜀"

# Google Cloud CLI (gcloud)
log "Google Cloud CLI 설치"
if have gcloud; then
  echo "  ✓ gcloud 이미 설치됨"
else
  brew install --cask gcloud-cli 2>/dev/null || brew install --cask google-cloud-sdk || echo "  ⚠ gcloud 설치 실패 → 건너뜀"
fi

# DCM (Dart Code Metrics)
log "DCM 설치"
brew tap CQLabs/dcm 2>/dev/null || true
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

# Android Studio/터미널이 표준 위치($ANDROID_HOME/cmdline-tools/latest)에서도 찾을 수 있도록 심볼릭 링크 연결
BREW_CMDLINE_TOOLS="$(brew --prefix)/share/android-commandlinetools/cmdline-tools/latest"
if [[ -d "$BREW_CMDLINE_TOOLS" ]]; then
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  [[ -e "$ANDROID_HOME/cmdline-tools/latest" ]] || ln -s "$BREW_CMDLINE_TOOLS" "$ANDROID_HOME/cmdline-tools/latest"
fi

SDKMANAGER="$(brew --prefix)/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$(brew --prefix)/share/android-commandlinetools/cmdline-tools/latest/bin/avdmanager"

if [[ -x "$SDKMANAGER" ]]; then
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

  # 최신 안정 버전 자동 탐지 (프리뷰 채널 제외) — pyenv 최신 버전 탐지와 동일한 방식
  SDK_LIST="$("$SDKMANAGER" --sdk_root="$ANDROID_HOME" --list 2>/dev/null)" || true
  LATEST_PLATFORM=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*platforms;android-[0-9]+' | tr -d ' ' | sort -t'-' -k2 -n | tail -1)
  LATEST_BUILD_TOOLS=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*build-tools;[0-9]+\.[0-9]+\.[0-9]+' | tr -d ' ' | sort -t';' -k2 -V | tail -1)
  LATEST_NDK=$(echo "$SDK_LIST" | grep -oE '^[[:space:]]*ndk;[0-9]+\.[0-9]+\.[0-9]+' | tr -d ' ' | sort -t';' -k2 -V | tail -1)

  ARCH_ABI="arm64-v8a"
  [[ "$(uname -m)" == "x86_64" ]] && ARCH_ABI="x86_64"
  SYSTEM_IMAGE="system-images;${LATEST_PLATFORM#platforms;};google_apis;${ARCH_ABI}"

  PACKAGES=("platform-tools" "emulator")
  [[ -n "$LATEST_BUILD_TOOLS" ]] && PACKAGES+=("$LATEST_BUILD_TOOLS")
  [[ -n "$LATEST_PLATFORM" ]] && PACKAGES+=("$LATEST_PLATFORM" "$SYSTEM_IMAGE")
  [[ -n "$LATEST_NDK" ]] && PACKAGES+=("$LATEST_NDK")

  echo "  설치할 패키지: ${PACKAGES[*]}"
  yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "${PACKAGES[@]}" \
    || echo "  ⚠ Android SDK 구성요소 일부 설치 실패 → 건너뜀"

  [[ -n "$LATEST_NDK" ]] && export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${LATEST_NDK#ndk;}"

  # AVD 생성 (이미 있으면 건너뜀)
  if [[ -x "$AVDMANAGER" && -n "$LATEST_PLATFORM" ]]; then
    AVD_NAME="Pixel_6_API_${LATEST_PLATFORM#platforms;android-}"
    if "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD_NAME"; then
      echo "  ✓ AVD($AVD_NAME) 이미 존재"
    else
      echo "no" | "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_6 \
        || echo "  ⚠ AVD 생성 실패 → 건너뜀 (Android Studio Device Manager에서 수동 생성 가능)"
    fi
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
echo "  android : $([[ -x "$ANDROID_HOME/platform-tools/adb" ]] && echo "✓ $ANDROID_HOME" || echo '❌')"
echo "  ndk     : $([[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME:-}" ]] && echo "✓ $ANDROID_NDK_HOME" || echo '❌')"
echo "  avd     : $([[ -n "${AVD_NAME:-}" ]] && "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD_NAME" && echo "✓ $AVD_NAME" || echo '❌')"

echo ""
echo "✅ 완료! 다음 단계:"
echo "  1. 새 터미널을 열거나: source ~/.zshrc"
echo "  2. p10k 테마 설정이 없다면: p10k configure"
echo "  3. Android Studio 실행 후 flutter doctor (SDK/NDK/AVD는 이미 자동 설치·구성됨)"
echo "  4. Claude Code 로그인: claude"
