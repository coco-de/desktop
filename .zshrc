[[ -o interactive ]] || return

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# 경고 메시지 억제 설정 추가
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

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
[[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# User configuration

source ~/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[[ -f "$HOME/.dart-cli-completion/zsh-config.zsh" ]] && . "$HOME/.dart-cli-completion/zsh-config.zsh" || true
## [/Completion]

## [Java]
export JAVA_HOME="$(/opt/homebrew/bin/brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

## [Ruby]
export PATH="$HOME/.rbenv/bin:$PATH"
if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi

# FVM 설정 개선
export PATH="$HOME/fvm/default/bin:$PATH"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PATH:$PUB_CACHE/bin"

## [Fastlane]
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
# Jira(Atlassian) MCP는 docker(colima) 데몬이 떠 있어야 붙는다. colima가 죽어 있으면
# claude를 켜도 그 세션 내내 Jira MCP가 조용히 끊긴 채로 남으므로(재시작 전엔 복구 안 됨),
# claude/cld 실행 직전에 매번 확인해 꺼져 있으면 자동으로 켠다.
_ensure_colima() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 && return 0
  if command -v colima >/dev/null 2>&1; then
    echo "🐳 colima(docker) 데몬이 꺼져 있어 Jira MCP가 연결되지 않습니다 — 자동으로 켭니다... (최초 실행 시 다소 걸릴 수 있습니다)"
    if colima start; then
      echo "  ✓ colima 시작됨 (Jira MCP 정상 연결)"
    else
      echo "  ⚠ colima 자동 시작 실패 → 'colima start'를 직접 실행한 뒤 다시 시도하세요"
    fi
  fi
}

claude() {
  _ensure_colima
  command claude --dangerously-skip-permissions "$@"
}

[[ -s "$HOME/.gvm/scripts/gvm" ]] && source "$HOME/.gvm/scripts/gvm"
[[ -d /opt/homebrew/opt/gradle@7/bin ]] && export PATH="/opt/homebrew/opt/gradle@7/bin:$PATH"

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# direnv
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
[[ -d /opt/homebrew/opt/libpq/bin ]] && export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# ── API 키 (값은 각자 발급해 채운다; 시크릿은 저장소에 커밋하지 말 것) ──
# 실제 키는 아래처럼 git 추적 안 되는 ~/.zshrc.local 에 넣는 것을 권장한다.
export GEMINI_API_KEY=''
export FIGMA_API_TOKEN=""
export FIGMA_ACCESS_TOKEN=""
export ZENHUB_API_TOKEN=""
export ANTHROPIC_API_KEY=""

# Shorebird
[[ -d "$HOME/.shorebird/bin" ]] && export PATH="$HOME/.shorebird/bin:$PATH"

# pipx
export PATH="$PATH:$HOME/.local/bin"

# Windsurf
[[ -d "$HOME/.codeium/windsurf/bin" ]] && export PATH="$HOME/.codeium/windsurf/bin:$PATH"

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
[[ -d /opt/homebrew/opt/node@22/bin ]] && export PATH="/opt/homebrew/opt/node@22/bin:$PATH"


if [[ -n $CURSOR_TRACE_ID ]]; then
  PROMPT_EOL_MARK=""
  test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
  precmd() { print -Pn "\e]133;D;%?\a" }
  preexec() { print -Pn "\e]133;C;\a" }
fi

export PATH=~/.npm-global/bin:$PATH

export PATH="$HOME/.local/bin:$PATH"

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

# Added by setup: make Dart global executables available
export PATH="$HOME/.pub-cache/bin:$PATH"

# Cursor 앱을 터미널 환경으로 실행
alias cursor-env="open -a Cursor --env PATH"

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
  _ensure_colima
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
