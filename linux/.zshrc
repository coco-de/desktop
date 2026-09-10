# ============================================================
# co:code 팀 표준 zsh 설정 (리눅스용)
#   coco-de/co-mac 의 .zshrc 를 Ubuntu/Debian 경로에 맞춰 옮긴 것이다.
#   달라진 곳: zsh-syntax-highlighting·JAVA_HOME·ANDROID_HOME 경로, colima→docker,
#             Homebrew 전용 PATH 3종과 macOS 전용 alias 제거.
#   개인 설정·API 키는 이 파일이 아니라 ~/.zshrc.local 에 둔다 (맨 아래에서 읽어들인다).
# ============================================================
[[ -o interactive ]] || return

# PATH 중복 제거 — 터미널을 중첩해서 열어도(tmux, claude, 서브셸 등) 같은 경로가 계속
# 쌓이지 않게 한다. 이 한 줄이 없으면 셸을 열 때마다 PATH가 11개씩 늘어나서,
# 몇 단계만 겹쳐도 80개가 넘어가고 명령을 찾는 속도가 그만큼 느려진다.
# (zsh가 알아서 앞쪽 항목만 남기고 뒤쪽 중복을 지우므로 우선순위는 그대로 유지된다.)
typeset -U path fpath PATH FPATH

# p10k의 경고 메시지만 숨기고 '즉시 프롬프트' 기능은 그대로 쓴다.
#   ⚠ 이 설정은 반드시 아래 instant prompt 블록보다 **위**에 있어야 효과가 있다.
#     (off로 두면 경고와 함께 즉시 프롬프트 자체가 꺼져 첫 화면이 느려진다.)
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# ~/.p10k.zsh 가 없어도 설정 마법사가 자동으로 뜨지 않게 한다(정상 프롬프트로 시작).
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
plugins=(
  git
  zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh
# 우분투는 apt 패키지(zsh-syntax-highlighting)가 /usr/share 밑에 넣는다.
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# User configuration

# powerlevel10k 테마는 위 ZSH_THEME 로 이미 로드된다. 아래 줄은 테마 로딩이 실패한
# PC(구버전 설치 등)에서만 대체 경로로 한 번 더 시도하는 안전장치다.
#   - 예전에는 조건 없이 source 해서 테마가 두 번 로드됐고,
#     ~/powerlevel10k 폴더가 없는 PC에서는 셸을 열 때마다 에러가 났다.
(( $+functions[p10k] )) || [[ ! -r ~/powerlevel10k/powerlevel10k.zsh-theme ]] || \
  source ~/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


## [Node / nvm]
# nvm은 읽어들이는 데만 약 0.4초가 걸려서, 예전에는 터미널을 열 때마다 그 시간을 그대로
# 기다려야 했다(전체 시작 시간의 절반 이상). 그래서 아래처럼 둘로 나눈다.
#   1) 설치돼 있는 node를 PATH에 바로 넣어 준다 → node/npm/npx는 지금까지처럼 즉시 사용 가능
#   2) nvm 명령 자체는 실제로 `nvm`을 칠 때만 읽어들인다 → 평소 시작 시간에 영향 없음
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # default 별칭이 구체 버전(v20.11.0 등)을 가리키면 그것을, 아니면 가장 최근에 설치된
  # 버전을 쓴다. 버전을 바꾸고 싶으면 `nvm use ...`를 쓰면 되고, 그때 nvm 전체가 로드된다.
  _nvm_default="$(<"$NVM_DIR/alias/default" 2>/dev/null)"
  if [[ "$_nvm_default" == v* && -d "$NVM_DIR/versions/node/$_nvm_default/bin" ]]; then
    export PATH="$NVM_DIR/versions/node/$_nvm_default/bin:$PATH"
  else
    _nvm_bin=("$NVM_DIR"/versions/node/*/bin(N/om))
    (( $#_nvm_bin )) && export PATH="${_nvm_bin[1]}:$PATH"
    unset _nvm_bin
  fi
  unset _nvm_default

  # `nvm`을 처음 부르는 순간에만 진짜 nvm을 읽어들이고, 그 호출을 그대로 넘겨준다.
  nvm() {
    unset -f nvm
    source "$NVM_DIR/nvm.sh"
    nvm "$@"
  }
fi

## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[[ -f "$HOME/.dart-cli-completion/zsh-config.zsh" ]] && . "$HOME/.dart-cli-completion/zsh-config.zsh" || true
## [/Completion]

## [Java]
# openjdk-17 이 설치된 PC에서만 JAVA_HOME 을 잡는다.
#   데비안/우분투는 JDK를 /usr/lib/jvm/java-17-openjdk-<아키텍처> 에 넣는다. 아키텍처
#   이름(amd64·arm64)이 PC마다 달라서 경로를 하드코딩하지 않고 있는 것을 찾아 쓴다.
#   (java 명령에서 역추적하지 않는 이유: 그 방법은 JRE만 깔린 PC에서 컴파일러가 없는
#    경로를 JAVA_HOME 으로 잡아 Gradle 빌드가 뒤늦게 실패한다.)
for _jdk in /usr/lib/jvm/java-17-openjdk-*; do
  if [[ -x "$_jdk/bin/javac" ]]; then
    export JAVA_HOME="$_jdk"
    export PATH="$JAVA_HOME/bin:$PATH"
    break
  fi
done
unset _jdk

## [Ruby]
export PATH="$HOME/.rbenv/bin:$PATH"
# zsh에서는 which보다 command -v 가 정확하다(별칭·함수에 속지 않음).
command -v rbenv >/dev/null && eval "$(rbenv init -)"

## [Python — pyenv]
# linux-setup.sh 5단계가 pyenv로 최신 3.x를 깔고 `pyenv global`로 기본 버전을 지정하지만,
# 그건 ~/.pyenv/version 파일에 기록만 할 뿐이다. 실제로 그 파이썬을 쓰려면 pyenv의
# shims 폴더가 PATH에 있어야 하는데, 이 설정이 없으면 새 터미널에서 `python`이
# "command not found"로 뜬다 (macOS에는 python 명령 자체가 없다).
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null && eval "$(pyenv init -)"

## [Android SDK]
# linux-setup.sh 4-e단계가 SDK·NDK·에뮬레이터·AVD를 이 경로에 설치·구성한다.
# 이 설정이 없으면 설치는 돼 있어도 터미널에서 adb·sdkmanager·emulator를 부를 수 없고,
# Gradle이 SDK 위치를 못 찾아 안드로이드 빌드가 실패한다.
# 리눅스 Android Studio 의 기본 SDK 경로다 (맥의 ~/Library/Android/sdk 에 해당).
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
if [[ -d "$ANDROID_HOME" ]]; then
  export PATH="$ANDROID_HOME/platform-tools:$PATH"
  export PATH="$ANDROID_HOME/emulator:$PATH"
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
fi

# FVM 설정 개선
export PATH="$HOME/fvm/default/bin:$PATH"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PATH:$PUB_CACHE/bin"

## [Fastlane]
# ⚠ fastlane 의 iOS 기능은 리눅스에서 쓸 수 없다(Xcode 필요). 안드로이드 배포에만 해당한다.
# 2FA SMS 수신 번호는 개인 정보라 저장소에 넣지 않는다. 필요하면 ~/.zshrc.local 에서 설정:
#   export SPACESHIP_2FA_SMS_DEFAULT_PHONE_NUMBER="+82..."

## [Go lang]
alias air='~/go/bin/air'

## [Kubernetes]
alias k="kubectl"
alias mk="minikube"

## 자주 사용하는 폴더로 이동 (없으면 무시됨)
alias cocode="cd ~/Development/cocode"

## Claude
# Jira(Atlassian) MCP는 docker 데몬이 떠 있어야 붙는다. 데몬이 죽어 있으면 claude를 켜도
# 그 세션 내내 Jira MCP가 조용히 끊긴 채로 남으므로(재시작 전엔 복구 안 됨),
# claude/cld 실행 직전에 매번 확인해 꺼져 있으면 자동으로 켠다.
#   맥은 colima 라는 별도 VM이 필요했지만 리눅스는 도커가 네이티브라 systemd 서비스만 켜면 된다.
_ensure_docker() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 && return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  echo "🐳 docker 데몬이 꺼져 있어 Jira MCP가 연결되지 않습니다 — 자동으로 켭니다..."
  if sudo systemctl start docker 2>/dev/null; then
    echo "  ✓ docker 시작됨 (Jira MCP 정상 연결)"
  else
    echo "  ⚠ docker 자동 시작 실패 → 'sudo systemctl start docker' 를 직접 실행한 뒤 다시 시도하세요"
  fi
  # 'docker: permission denied' 가 뜬다면 그룹 가입이 안 된 것이다:
  #   sudo usermod -aG docker $USER  → 로그아웃 후 다시 로그인
  #   (linux-setup.sh --system-only 로도 다시 잡을 수 있다)
}

claude() {
  _ensure_docker
  command claude --dangerously-skip-permissions "$@"
}

[[ -s "$HOME/.gvm/scripts/gvm" ]] && source "$HOME/.gvm/scripts/gvm"
# gradle 은 Android Studio 와 Flutter 가 프로젝트별 wrapper(gradlew)로 알아서 받는다.

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# direnv
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
# psql 등 postgres 클라이언트는 apt(postgresql-client)가 /usr/bin 에 넣으므로 PATH 추가가 필요 없다.

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# ── API 키 ────────────────────────────────────────────────────────────────────
# 개인 API 키는 여기에 두지 말고, git이 추적하지 않는 ~/.zshrc.local 에 넣는다:
#   export GEMINI_API_KEY="..."
#   export FIGMA_API_TOKEN="..."
#   export ANTHROPIC_API_KEY="..."
#
# ⚠ 예전처럼 `export ANTHROPIC_API_KEY=""` 같은 '빈 값'을 여기에 적어두면 안 된다.
#   ① 이미 환경에 들어 있던 진짜 키를 빈 값으로 덮어써 버리고,
#   ② 도구에 따라 '키가 있다'고 판단해 인증 없이 동작하다 실패한다
#      (zenhub MCP가 '✔ Connected'로 보이면서 호출은 "Missing Authorization token"으로
#       실패하던 것이 바로 이 경우다 — linux-setup.sh 8.5단계 주석 참고).
#   팀 공용 토큰(ZENHUB/JIRA/SLACK 등)은 linux-setup.sh가 1Password에서 읽어 이 파일 끝에
#   직접 넣어주므로, 여기에 미리 빈 줄을 만들어 둘 필요가 없다.

# Shorebird
[[ -d "$HOME/.shorebird/bin" ]] && export PATH="$HOME/.shorebird/bin:$PATH"

# Windsurf
[[ -d "$HOME/.codeium/windsurf/bin" ]] && export PATH="$HOME/.codeium/windsurf/bin:$PATH"

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"


if [[ -n $CURSOR_TRACE_ID ]]; then
  PROMPT_EOL_MARK=""
  test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
  precmd() { print -Pn "\e]133;D;%?\a" }
  preexec() { print -Pn "\e]133;C;\a" }
fi

export PATH="$HOME/.npm-global/bin:$PATH"

# pipx / Claude Code 공식 인스톨러 경로
export PATH="$HOME/.local/bin:$PATH"

# Dart 전역 실행 파일 (dart pub global activate)
export PATH="$HOME/.pub-cache/bin:$PATH"


# Antigravity
[[ -d "$HOME/.antigravity/antigravity/bin" ]] && export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
export PATH="$PATH:$HOME/bin"

# ─── Claude Code aliases ───────────────────────────────────────────────────────
# Agent Teams, MCP, skip-permissions 는 ~/.claude/settings.json 에서 관리
# settings.json: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=4, TEAMMATE_MODE=split-pane
# .claude/agents/ 의 프로젝트 에이전트가 자동 로딩됨 (CLI --agents 불필요)

_claude_session_name() {
  pwd | awk -F'/' '{print $(NF-1)"/"$NF}'
}

# cld : Agent Teams 모드 (프로젝트 에이전트 자동 로딩)
cld() {
  _ensure_docker
  command claude \
    --dangerously-skip-permissions \
    --name "$(_claude_session_name)" \
    --remote-control \
    --model claude-sonnet-5 \
    --settings '{"ultracode": true}' \
    "$@"
}

# ──────────────────────────────────────────────────────────────────────────────

# Tmux
alias tns="tmux new-session -A -s"

# 개인용 오버라이드/시크릿: git 추적 안 됨. 각자 API 키 등을 여기에 둔다.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
