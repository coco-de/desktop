#!/bin/bash
# ============================================================
# 맥 초기 개발환경 세팅 스크립트
# 전제: Homebrew, Xcode 설치 완료
# 실행: chmod +x mac-setup.sh && ./mac-setup.sh
#   └ 이미 세팅한 맥에서 토큰(환경변수)만 다시 주입하려면: ./mac-setup.sh --env-only
#
# 기존 맥의 테마/설정을 그대로 가져오려면, 기존 맥에서
#   ~/.zshrc, ~/.p10k.zsh
# 를 이 스크립트와 같은 폴더에 복사해 두세요. (있으면 그대로 사용)
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------
# 실행 옵션 파싱
#   (옵션 없음) : 전체 설치 (1~9단계)
#   --env-only  : 1Password(op)에서 팀 공용 토큰만 다시 읽어 ~/.zshrc에 주입 (8.5~8.8단계만)
#   -h, --help  : 사용법 출력
#   모르는 옵션은 즉시 에러 종료한다 — 오탈자(예: --env-onyl)가 조용히
#   수 분짜리 전체 설치로 이어지는 사고를 막기 위함이다.
# ------------------------------------------------------------
usage() {
  cat <<'USAGE'
사용법: ./mac-setup.sh [옵션]

  (옵션 없음)   co:code 팀 표준 개발환경 전체 설치 (1~9단계)
  --env-only    1Password(op)에서 팀 공용 토큰(ZENHUB_API_TOKEN·JIRA_API_TOKEN·
                SLANG_GPT_API_KEY·DCM_EMAIL·DCM_CI_KEY)만 다시 읽어 ~/.zshrc에
                주입합니다. 앱/도구 설치 단계는 전부 건너뜁니다.
                (토큰이 바뀌었거나, 설치 때 토큰 주입을 건너뛴 경우에 사용)
  -h, --help    이 도움말을 표시합니다
USAGE
}

ENV_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --env-only) ENV_ONLY=1 ;;
    -h|--help)  usage; exit 0 ;;
    *)
      echo "❌ 알 수 없는 옵션: $arg"
      echo ""
      usage
      exit 1
      ;;
  esac
done

# Homebrew 경로 (Apple Silicon / Intel 자동 감지)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif (( ENV_ONLY )); then
  # --env-only는 아무것도 설치하지 않고 op만 쓰므로 Homebrew가 없어도 계속 진행한다
  :
else
  echo "❌ Homebrew가 없습니다. 먼저 설치하세요: https://brew.sh"
  exit 1
fi

log()  { echo ""; echo "▶ $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 모든 y/n 확인 프롬프트 자동 통과
export NONINTERACTIVE=1          # Homebrew 비대화 모드
export CI=true                   # 많은 CLI가 CI 모드에서 프롬프트 생략

# ============================================================
# 실행 단계 맵 (섹션 번호는 삽입 이력상 비순차 — 아래가 실제 실행 순서)
#   1.   GUI 앱 (brew cask: 개발툴·브라우저·1Password·op 등)
#   1.5. Xcode 설치 확인/자동 설치(mas, App Store 로그인 필요) + 개발자 도구 전환
#        (CLT만 활성화돼 있으면 Xcode.app으로 xcode-select 전환 + 최초 실행 동의,
#        sudo 암호 필요 · TTY에서만 시도)
#   2.   Claude Code CLI
#   2.5. Claude MCP (figma 플러그인 + zenhub·jira(mcp-atlassian) 토큰 등록 + maestro·flutter-mcp-toolkit)
#        └ 설정 기록/자체완결 설치라 런타임(node·dart)보다 앞서도 무해.
#          런타임은 새 세션에서 MCP 서버가 실제 뜰 때만 필요 (그땐 스크립트 완료 후).
#   2.6. 다른 AI 코딩 CLI (codex=OpenAI(brew cask) · agy=Google Antigravity(공식 스크립트→~/.local/bin))
#   3.   CLI 도구 (brew formulae: go·gh·jq·docker 등)
#   3.2. Git 사용자 이메일 (git config --global user.email, TTY면 입력·s로 건너뜀)
#   3.5. cocode-skills 팀 플러그인 (사설 레포 install.sh, gh 인증 필요)
#   4.   Flutter/Dart(FVM) · Dart 글로벌 · gcloud · DCM · Android SDK/AVD
#   5.   Python (pyenv)
#   6.   Node.js (nvm)
#   6.5. Claude Code 상태줄 (ccstatusline: npx 기반, node 설치 직후에 실행 · ~/.claude/settings.json 자동 등록)
#   7.   oh-my-zsh + powerlevel10k
#   7.5. Terminal.app 프로필 폰트 자동 적용 (MesloLGS NF, Terminal.app 실행 중일 때만)
#   8.   ~/.zshrc / ~/.p10k.zsh 반영
#   8.5. ZENHUB_API_TOKEN 주입 (1Password op read → .zshrc, TTY면 안내 후 Enter)
#   8.6. JIRA_API_TOKEN 주입 (1Password op read → .zshrc, mcp-atlassian Docker MCP용)
#   8.7. SLANG_GPT_API_KEY 주입 (1Password op read → .zshrc, slang_gpt 다국어 자동 번역용)
#   8.8. DCM_EMAIL·DCM_CI_KEY 주입 (1Password op read → .zshrc, DCM CI 라이선스 인증용)
#   9.   설치 검증 + 다음 단계 안내
# 공통 규칙: 모든 단계 멱등(이미 설치 시 스킵) · 실패해도 ⚠ 후 계속 · 시크릿 미커밋
# 실행 옵션: 옵션 없음=전체 실행 · --env-only=8.5~8.8(토큰 주입)만 재실행 · -h/--help=사용법
# ============================================================

# ============================================================
# 설치 단계 시작 (1~8단계) — --env-only 실행 시 이 블록 전체를 건너뛴다
#   기존 코드를 옮기지 않고 그대로 감싸기만 했으므로, 블록 안쪽 본문은
#   들여쓰기 없이 유지된다 (짝이 되는 fi는 8.5단계 직전에 있다)
# ============================================================
if (( ! ENV_ONLY )); then

# ------------------------------------------------------------
# 1. GUI 앱 (brew cask)
# ------------------------------------------------------------
log "GUI 앱 설치 (Android Studio, Slack, Figma, Claude Desktop, Chrome, Dia, 1Password, Tailscale, Orca, Lumide, Zed) + 1Password CLI(op — 앱이 아닌 터미널 도구)"

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
install_cask claude                 "Claude.app"
install_cask google-chrome          "Google Chrome.app"
install_cask thebrowsercompany-dia  "Dia.app"
install_cask 1password              "1Password.app"
# 1Password CLI: 터미널에서 1Password 금고를 읽는 `op` 명령. 앱이 아니라 CLI라 /Applications에 없다.
#   이 스크립트에서는 8.5단계에서 팀 공용 ZenHub 토큰을 읽어오는 데 쓴다 (설정 방법은 8.5단계 주석 참고).
install_cask 1password-cli          ""
install_cask tailscale              "Tailscale.app"
install_cask orca                   "Orca.app"                 stablyai/orca/orca
install_cask lumide                 "Lumide.app"
install_cask zed                    "Zed.app"

# ------------------------------------------------------------
# 1.5. Xcode 설치 확인/자동 설치 + 개발자 도구 전환
#   Xcode.app이 없으면 mas(App Store CLI)로 자동 설치를 시도한다(App Store에 Apple ID로
#   로그인돼 있어야 함 — mas는 로그인 자체는 대신해줄 수 없다). 수십 GB 다운로드라 네트워크
#   상태에 따라 수십 분~수 시간 걸릴 수 있다. mas 미설치·미로그인이면 조용히 건너뛰고
#   App Store에서 직접 설치하도록 안내한다(기존 "전제 조건" 방식과 동일하게 계속 진행).
#
#   Xcode.app은 있지만 Command Line Tools만 활성화된 상태에서 xcodebuild를 실행하면
#   "requires Xcode, but active developer directory ... CommandLineTools" 에러가 난다
#   (cocoapods `pod install`, iOS 빌드 등도 같은 이유로 실패한다). Xcode.app이 있는데
#   xcode-select가 CLT를 가리키면 Xcode.app으로 전환하고 최초 실행 동의(-runFirstLaunch)까지
#   진행한다. sudo 암호 입력이 필요해 TTY에서만 시도한다.
# ------------------------------------------------------------
log "Xcode 설치 확인/자동 설치 + 개발자 도구 전환"

if [[ ! -d /Applications/Xcode.app ]]; then
  brew list mas >/dev/null 2>&1 || brew install mas || true
  if have mas && mas account >/dev/null 2>&1; then
    echo "  · Xcode.app 없음 → mas(App Store CLI)로 자동 설치 시도 (수십 GB 다운로드 · 네트워크에 따라 수십 분~수 시간 소요될 수 있습니다)"
    mas install 497799835 \
      && echo "  ✓ Xcode 설치 완료 (mas)" \
      || echo "  ⚠ mas install 실패 → 건너뜀 (App Store에서 직접 설치: https://apps.apple.com/app/xcode/id497799835)"
  elif have mas; then
    echo "  ⚠ mas가 App Store 계정에 로그인돼 있지 않음 → Xcode 자동 설치 건너뜀 (App Store 앱에 Apple ID로 로그인 후 재실행하거나 직접 설치: https://apps.apple.com/app/xcode/id497799835)"
  else
    echo "  ⚠ mas(App Store CLI) 설치 실패 → Xcode 자동 설치 건너뜀 (App Store에서 직접 설치: https://apps.apple.com/app/xcode/id497799835)"
  fi
fi

if [[ ! -d /Applications/Xcode.app ]]; then
  echo "  ⚠ /Applications/Xcode.app 없음 → 개발자 도구 전환 건너뜀 (Xcode 설치 후 재실행하면 자동 전환됩니다)"
elif [[ "$(xcode-select -p 2>/dev/null)" == "/Applications/Xcode.app/Contents/Developer" ]]; then
  echo "  ✓ xcode-select가 이미 Xcode.app을 가리킴"
elif [[ -t 0 ]]; then
  echo "  · xcode-select가 Command Line Tools를 가리키고 있음 → Xcode.app으로 전환 (sudo 암호 입력 필요)"
  if sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer; then
    sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 \
      && echo "  ✓ Xcode 전환 + 최초 실행(라이선스 동의) 완료" \
      || echo "  ⚠ xcodebuild -runFirstLaunch 실패 → 건너뜀 (수동: sudo xcodebuild -runFirstLaunch)"
  else
    echo "  ⚠ xcode-select 전환 실패 → 건너뜀 (수동: sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer)"
  fi
else
  echo "  ⚠ 비대화형 실행 → Xcode 전환 건너뜀. 수동: sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch"
fi

# ------------------------------------------------------------
# 2. Claude Code CLI
#   공식 설치 스크립트(https://claude.ai/install.sh)로 설치한다 — brew cask 대신
#   공식 홈페이지 권장 방식(자동 업데이트 내장). 바이너리가 ~/.local/bin/claude에
#   설치되므로, 같은 실행 세션의 뒷단계(2.5 MCP 설치)와 멱등 체크가 바로 동작하도록
#   PATH에 먼저 반영한다. 기존에 brew cask로 설치된 맥은 감지 후 건너뜀(제거하지 않음).
# ------------------------------------------------------------
log "Claude Code CLI 설치 (공식 설치 스크립트)"
export PATH="$HOME/.local/bin:$PATH"
if have claude; then
  echo "  ✓ claude 이미 설치됨"
else
  curl -fsSL https://claude.ai/install.sh | bash || true
  # 성공 판정은 인스톨러 종료 코드가 아니라 바이너리 존재로 확인한다
  # (curl 실패 시 bash가 빈 입력으로 0 종료하는 false-success, 인스톨러가
  #  설치 후 부수 단계에서 비0 종료하는 false-failure 모두 방지)
  if have claude; then
    echo "  ✓ claude 설치 완료 (~/.local/bin/claude)"
  else
    echo "  ⚠ claude 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://claude.ai/install.sh | bash)"
  fi
fi

# ------------------------------------------------------------
# 2.5. Claude Code MCP 서버 / 플러그인 (jira=atlassian, figma, zenhub, maestro, flutter-mcp-toolkit)
#   MCP는 3계층으로 설치된다:
#     ① 플러그인 계층  : claude plugin install (figma, flutter-mcp-toolkit) — 아래에서 자동
#     ② 로컬 바이너리   : maestro CLI·flutter-mcp-toolkit CLI(아래), marionette_mcp·dart mcp-server(4단계에서 설치)
#     ③ 인증 계층      : figma OAuth는 최초 1회 `/mcp`에서 수동 로그인 (자동화 불가),
#                        zenhub·jira는 ~/.zshrc의 팀 공용 토큰(런타임 확장)으로 인증 — 토큰 값은 커밋 금지,
#                        flutter-mcp-toolkit은 별도 인증 불필요
#   ※ jira(atlassian)는 과거 OAuth 플러그인이었으나, 매번 `/mcp` 로그인하는 수고를 없애려고 팀 공용
#     토큰 방식으로 전환했다. 공식 원격 MCP(mcp.atlassian.com, Rovo)는 조직 Rovo 엔타이틀먼트로 막혀,
#     Jira REST API에 토큰으로 직접 붙는 오픈소스 MCP(sooperset/mcp-atlassian, Docker)로 붙인다.
#     → 개발팀 공용 계정(dev@cocode.im)의 Jira 토큰만 있으면 되고 Rovo 권한이 필요 없다. (토큰 주입은 8.6단계)
#     ⚠ 런타임에 colima/docker 데몬이 떠 있어야 이 MCP가 뜬다(팀은 backend 개발로 docker 상시 사용).
#   ※ marionette·dart·figma(serve) MCP 정의는 사설 cocode-skills 플러그인 번들에서 제공됨
#     (coco-de/skills의 install.sh — 아래 3.5단계에서 설치)
# ------------------------------------------------------------
log "Claude Code MCP 설치 (figma 플러그인 + zenhub·jira 토큰 등록 + maestro CLI + flutter-mcp-toolkit)"

if have claude; then
  # 공식 마켓플레이스 등록 (이미 있으면 무시)
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 || true

  # 원격 OAuth 플러그인(figma): 설치는 자동, 로그인은 최초 1회 `/mcp`에서 수동
  #   ※ atlassian은 더 이상 OAuth 플러그인으로 설치하지 않는다(아래 토큰 방식으로 대체).
  for p in figma; do
    if claude plugin list 2>/dev/null | grep -q "${p}@claude-plugins-official"; then
      echo "  ✓ ${p} 플러그인 이미 설치됨"
    else
      claude plugin install "${p}@claude-plugins-official" --scope user >/dev/null 2>&1 \
        && echo "  ✓ ${p} 플러그인 설치 (최초 1회 /mcp 로그인 필요)" \
        || echo "  ⚠ ${p} 플러그인 설치 실패 → 건너뜀 (claude 로그인 후 재시도)"
    fi
  done

  # atlassian(jira): 예전엔 OAuth 플러그인이었으나 토큰 방식으로 전환 →
  #   기존에 설치된 atlassian OAuth 플러그인이 있으면 제거해야 아래 토큰 등록이 'atlassian' 이름을 차지한다.
  if claude plugin list 2>/dev/null | grep -q "atlassian@claude-plugins-official"; then
    claude plugin uninstall atlassian@claude-plugins-official >/dev/null 2>&1 \
      && echo "  · 기존 atlassian OAuth 플러그인 제거 (토큰 방식으로 전환)" \
      || echo "  ⚠ 기존 atlassian OAuth 플러그인 제거 실패 → 수동 제거 필요(claude plugin uninstall atlassian@claude-plugins-official)"
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
    && echo "  ✓ zenhub MCP 등록/갱신 (토큰은 8.5단계에서 1Password 공용 항목으로 주입)" \
    || echo "  ⚠ zenhub MCP 등록 실패 → 건너뜀"

  # 기존 Rovo 방식 atlassian MCP가 남아 있으면 제거(엔타이틀먼트로 막혀 미동작) → 아래 mcp-atlassian으로 대체.
  #   grep 없이 무조건 remove — 없을 때 실패해도 무해(|| true).
  claude mcp remove atlassian >/dev/null 2>&1 && echo "  · 기존 Rovo atlassian MCP 제거 (REST 직결 방식으로 전환)" || true

  # jira MCP = sooperset/mcp-atlassian (Docker) — Jira Cloud REST API에 토큰으로 직접 붙는다(Rovo 우회).
  #   인증: JIRA_URL/JIRA_USERNAME/JIRA_API_TOKEN 환경변수 → 서버가 내부적으로 Basic(email:token) 처리.
  #   토큰만 비밀이라 --env 'JIRA_API_TOKEN=${JIRA_API_TOKEN}'로 리터럴 등록(claude가 런타임에 ~/.zshrc 값으로 확장,
  #   config에는 '${JIRA_API_TOKEN}' 문자열만 저장 — 값 커밋/노출 없음). URL·이메일은 비밀 아님(직접 기입).
  #   먼저 이미지 pull(없으면 최초 claude 실행 때 pull되며 지연). docker 데몬 필요.
  #   ⚠ zenhub와 동일하게 항상 remove 후 add — 정의가 바뀐 업데이트(이미지 태그·env·args 변경)를 재실행만으로 반영.
  if have docker && docker info >/dev/null 2>&1; then
    docker pull ghcr.io/sooperset/mcp-atlassian:latest >/dev/null 2>&1 \
      && echo "  · mcp-atlassian 도커 이미지 준비됨" \
      || echo "  ⚠ mcp-atlassian 이미지 pull 실패 → 최초 사용 시 자동 pull(지연) 또는 수동 확인"
  else
    echo "  ⚠ docker 데몬 미동작 → 이미지 pull 생략 (colima start 후 재실행 권장, 등록은 계속)"
  fi
  claude mcp remove mcp-atlassian >/dev/null 2>&1 || true
  claude mcp add mcp-atlassian --scope user \
    --env JIRA_URL=https://laputa.atlassian.net \
    --env JIRA_USERNAME=dev@cocode.im \
    --env 'JIRA_API_TOKEN=${JIRA_API_TOKEN}' \
    -- docker run --rm -i -e JIRA_URL -e JIRA_USERNAME -e JIRA_API_TOKEN \
       ghcr.io/sooperset/mcp-atlassian:latest --transport stdio >/dev/null 2>&1 \
    && echo "  ✓ mcp-atlassian(jira) MCP 등록/갱신 (토큰은 8.6단계에서 1Password 공용 항목으로 주입)" \
    || echo "  ⚠ mcp-atlassian 등록 실패 → 건너뜀"
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
# 2.6. 다른 AI 코딩 CLI (codex, antigravity(agy))
#   Claude Code와 나란히 터미널에서 쓰는 AI 코딩 에이전트 두 가지를 추가로 설치한다.
#     · codex (OpenAI): 공식 Homebrew cask로 설치. 바이너리는 `codex`. 최초 실행 시 ChatGPT 계정 로그인.
#     · agy   (Google Antigravity CLI): 은퇴한 Gemini CLI의 공식 후속 도구. 단일 Go 바이너리라
#             Claude Code와 똑같이 공식 설치 스크립트로 ~/.local/bin/agy 에 설치한다(node·python 불필요).
#             brew로도 받을 수 있으나 GUI 앱과 바이너리 충돌 사례가 있어 공식 스크립트를 쓴다.
#             최초 실행 시 Google 계정으로 로그인.
#   두 도구 모두 멱등(이미 있으면 건너뜀) · 실패 시 ⚠ 후 계속.
# ------------------------------------------------------------
log "다른 AI 코딩 CLI 설치 (codex, antigravity(agy))"

# codex (OpenAI) — 공식 Homebrew cask
if have codex; then
  echo "  ✓ codex 이미 설치됨"
else
  brew install --cask codex \
    && echo "  ✓ codex 설치 완료 (최초 실행 시 codex 로 ChatGPT 로그인)" \
    || echo "  ⚠ codex 설치 실패 → 건너뜀 (수동 설치: brew install --cask codex)"
fi

# agy (Google Antigravity CLI) — 공식 설치 스크립트 (Claude Code와 동일 패턴, ~/.local/bin)
#   같은 실행 세션의 아래 단계·검증에서 바로 잡히도록 PATH를 먼저 반영한다(section 2와 동일).
export PATH="$HOME/.local/bin:$PATH"
if have agy; then
  echo "  ✓ agy(antigravity) 이미 설치됨"
else
  curl -fsSL https://antigravity.google/cli/install.sh | bash || true
  # 성공 판정은 인스톨러 종료 코드가 아니라 바이너리 존재로 확인한다 (Claude Code와 동일 이유)
  if have agy; then
    echo "  ✓ agy(antigravity) 설치 완료 (~/.local/bin/agy, 최초 실행 시 agy 로 Google 로그인)"
  else
    echo "  ⚠ agy 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://antigravity.google/cli/install.sh | bash)"
  fi
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
# 4. Flutter/Dart 및 SDK 일괄 (하위 단계는 각 log 라인 참고)
#    4-a FVM+Flutter · 4-b Dart 글로벌 패키지 · 4-c gcloud · 4-d DCM · 4-e Android SDK/AVD
# ------------------------------------------------------------
# 4-a. FVM + Flutter stable 글로벌 설치
log "FVM 설치 및 Flutter stable 글로벌 설정"
# 최신 Homebrew는 서드파티 tap을 신뢰 등록(brew trust)해야 설치를 허용한다.
# (brew trust 명령이 없는 구버전 Homebrew에서는 그냥 건너뜀)
brew tap leoafarias/fvm 2>/dev/null || true
brew trust leoafarias/fvm 2>/dev/null || true
brew list fvm >/dev/null 2>&1 && echo "  ✓ fvm 이미 설치됨" || brew install fvm
yes | fvm install stable
yes | fvm global stable --force 2>/dev/null || yes | fvm global stable
export PATH="$HOME/fvm/default/bin:$PATH"

# 4-b. Dart 글로벌 패키지 (serverpod_cli, marionette_mcp, mcp_server_dart)
log "Dart 글로벌 패키지 설치"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PUB_CACHE/bin:$PATH"
dart pub global activate serverpod_cli 4.0.0-beta.0 || echo "  ⚠ serverpod_cli 설치 실패 → 건너뜀"
dart pub global activate marionette_mcp || echo "  ⚠ marionette_mcp 설치 실패 → 건너뜀"
dart pub global activate mcp_server_dart || echo "  ⚠ mcp_server_dart 설치 실패 → 건너뜀"

# 4-c. Google Cloud CLI (gcloud)
log "Google Cloud CLI 설치"
if have gcloud; then
  echo "  ✓ gcloud 이미 설치됨"
else
  brew install --cask gcloud-cli 2>/dev/null || brew install --cask google-cloud-sdk || echo "  ⚠ gcloud 설치 실패 → 건너뜀"
fi

# 4-d. DCM (Dart Code Metrics)
#   여기서는 dcm CLI 자체만 설치한다. CI/자동화 인증용 이메일+키(DCM_EMAIL·DCM_CI_KEY)는
#   ZenHub·Jira·Slang GPT 토큰처럼 1Password 팀 공용 항목에서 읽어 아래 8.8단계에서 주입한다.
log "DCM 설치"
# 서드파티 tap 신뢰 등록 — 없으면 최신 Homebrew가 "untrusted tap" 에러로 설치를 거부한다
brew tap CQLabs/dcm 2>/dev/null || true
brew trust CQLabs/dcm 2>/dev/null || true
brew list dcm >/dev/null 2>&1 && echo "  ✓ dcm 이미 설치됨" || yes | brew install dcm || echo "  ⚠ dcm 설치 실패 → 건너뜀"

# Android SDK 구성요소 (cmdline-tools, platform-tools, build-tools, platforms, NDK, 에뮬레이터, AVD)
# Android Studio(GUI)를 직접 실행해 SDK 설치 마법사를 거치지 않아도 되도록,
# brew의 cmdline-tools만으로 표준 SDK 위치($ANDROID_HOME)에 필요한 구성요소를 전부 설치한다.
# 4-e. Android SDK 구성요소
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
# 6.5. Claude Code 상태줄(statusline) — ccstatusline
#   Claude Code 하단 상태줄을 모델·세션 비용·컨텍스트 사용량·git 상태까지 보여주는
#   두 줄짜리 정보 표시줄로 바꿔 주는 대화형 TUI 도구다(Node.js 기반, npx로 그때그때
#   실행 — 별도 설치가 필요 없다: https://github.com/sirmalloc/ccstatusline).
#   실행 후 위젯을 구성해 저장하면 ~/.claude/settings.json에 statusLine으로 등록된다.
#   대화형 TUI라 이 스크립트가 값을 자동으로 채워 넣을 수는 없어, stdin을 막고
#   한 번 시도만 해 본다(실패해도 무해) · 실제 구성은 '다음 단계' 안내에서 사람이 진행.
#   ※ npx가 node를 필요로 하므로 6단계(Node.js) 바로 뒤에 둔다.
# ------------------------------------------------------------
log "Claude Code 상태줄 확인 (ccstatusline — npx 기반, 사전 설치 불필요)"

if grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "  ✓ 상태줄 이미 등록됨 (~/.claude/settings.json)"
else
  npx -y ccstatusline@latest </dev/null >/dev/null 2>&1 || true
  if grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo "  ✓ 상태줄 등록 완료 (~/.claude/settings.json — Claude Code에서 바로 적용)"
  else
    echo "  ⚠ 상태줄 자동 등록 안 됨 → 대화형 도구라 사람이 직접 한 번 실행해야 합니다 (수동 설정: npx -y ccstatusline@latest, 아래 '다음 단계' 참고)"
  fi
fi

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
# 7.5. Terminal.app 프로필 폰트 자동 적용
#   위에서 설치한 MesloLGS Nerd Font는 "설치"만으로는 powerlevel10k 아이콘이 제대로
#   보이지 않는다 — 터미널 앱이 실제로 그 폰트를 쓰도록 프로필에서 선택해야 한다.
#   macOS 기본 Terminal.app은 AppleScript로 기본/시작 프로필 폰트를 자동 지정할 수 있어
#   여기서 대신 처리한다(폰트 파일에서 PostScript 이름을 직접 추출해 로케일 영향을 받지
#   않는다). 고정폭 렌더링이 중요한 터미널 용도라 "Mono" 변형을 우선한다.
#   iTerm2 등 다른 터미널 앱은 자동화 대상이 아니라 계속 수동 설정이 필요하다.
#   (Terminal.app을 새로 띄우면 다른 터미널에서 실행 중이어도 원치 않는 창이 열릴 수 있어,
#   현재 실행 터미널이 Terminal.app일 때만 시도한다.)
# ------------------------------------------------------------
log "Terminal.app 프로필 폰트 자동 적용 (MesloLGS NF)"
if [[ "$TERM_PROGRAM" != "Apple_Terminal" ]]; then
  echo "  · Terminal.app이 아닌 터미널(${TERM_PROGRAM:-미확인})에서 실행 중 → 자동 적용 건너뜀 (해당 터미널 앱 환경설정에서 폰트를 MesloLGS NF로 직접 변경해주세요)"
else
  MESLO_FONT_FILE="$(find "$HOME/Library/Fonts" /Library/Fonts -maxdepth 1 -iname '*MesloLGS*Mono*Regular*.ttf' 2>/dev/null | head -1)"
  [[ -z "$MESLO_FONT_FILE" ]] && \
    MESLO_FONT_FILE="$(find "$HOME/Library/Fonts" /Library/Fonts -maxdepth 1 -iname '*MesloLGS*Regular*.ttf' 2>/dev/null | head -1)"
  MESLO_PS_NAME=""
  [[ -n "$MESLO_FONT_FILE" ]] && \
    MESLO_PS_NAME="$(strings "$MESLO_FONT_FILE" 2>/dev/null | grep -E '^[A-Za-z0-9]+-Regular$' | head -1)"

  if [[ -z "$MESLO_PS_NAME" ]]; then
    echo "  ⚠ MesloLGS 폰트 파일을 찾지 못함 → 자동 적용 건너뜀 (Terminal 환경설정 > 프로필 > 폰트를 MesloLGS NF로 직접 변경)"
  elif osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Terminal"
    set font name of default settings to "$MESLO_PS_NAME"
    set font name of startup settings to "$MESLO_PS_NAME"
    try
        set font name of front window to "$MESLO_PS_NAME"
    end try
end tell
APPLESCRIPT
  then
    echo "  ✓ Terminal.app 프로필 폰트를 ${MESLO_PS_NAME}로 자동 적용 (새 창부터 적용되며, 지금 이 창도 즉시 반영됩니다)"
  else
    echo "  ⚠ Terminal.app 폰트 자동 적용 실패 → 건너뜀 (환경설정 > 프로필 > 폰트를 MesloLGS NF로 직접 변경)"
  fi
fi

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
  echo "  ✓ ~/.zshrc에 ~/.local/bin PATH 추가 (Claude Code)"
fi

fi  # ══ 설치 단계(1~8) 끝 — 여기부터(8.5~8.8 토큰 주입)는 --env-only 실행 시에도 수행된다 ══

# --env-only 가드: 아직 전체 세팅을 한 번도 하지 않은 맥이면 토큰을 붙일 ~/.zshrc 골격이
#   없다. 빈 .zshrc를 새로 만들어 토큰만 꽂으면 PATH·테마 등이 빠진 반쪽짜리 설정이 되므로,
#   전체 설치를 먼저 하도록 안내하고 종료한다.
if (( ENV_ONLY )) && [[ ! -f "$HOME/.zshrc" ]]; then
  echo ""
  echo "❌ ~/.zshrc 가 없습니다 — 아직 전체 세팅을 한 번도 하지 않은 맥으로 보입니다."
  echo "   먼저 옵션 없이 전체 설치를 실행해 주세요: ./mac-setup.sh"
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
#   실행 순서상 section 8에서 .zshrc가 확정된 뒤에 실행한다.
#
#   [동작 전제]
#   1) op(1password-cli) 설치됨 — 1단계에서 cask로 설치
#   2) 1Password 앱에 팀 계정(team-cocodeinc)으로 로그인
#   3) 1Password 앱 > 설정(⌘,) > 개발자 > '1Password CLI와 통합' 체크
#      → 이 통합을 켜야 op가 앱의 로그인 세션을 그대로 빌려 쓴다.
#        (안 켜면 op는 등록된 계정이 없어 실패한다. 'op account add'를 직접 할 필요는 없다.)
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "ZenHub API Token" > credential 필드
#     (계정이 여러 개인 사용자도 동작하도록 --account로 팀 계정을 명시)
#
#   [준비가 안 됐을 때]
#   터미널(TTY)이면 여기서 멈춰 한글 안내를 띄우고, 1Password 설정을 마친 뒤 Enter로 재시도한다.
#   파이프 실행(TTY 없음)이면 멈추지 않고 건너뜀(설정 후 스크립트 재실행 시 자동 주입).
# ------------------------------------------------------------
ZENHUB_TOKEN_OP_ACCOUNT="team-cocodeinc.1password.com"                # 팀 1Password 계정 (비밀 아님)
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

# op에 쓸 수 있는 계정이 등록돼 있는지 확인. 등록됨 0, 아니면 1.
#   ⚠ `op account list`는 계정이 하나도 없어도 종료코드 0에 빈 목록('[]')만 출력한다.
#     따라서 종료코드가 아니라 '출력 내용'으로 판단해야 한다.
op_has_account() {
  local accounts
  accounts="$(op account list --format=json 2>/dev/null </dev/null)" || return 1
  [[ -n "$accounts" && "$accounts" != "[]" ]]
}

# op read → ~/.zshrc의 ZENHUB_API_TOKEN 주입. 성공 시 0, 실패 시 1 반환.
#   ⚠ op 호출에는 반드시 stdin을 </dev/null로 막는다.
#     계정이 등록되지 않은 상태의 op는 "Do you want to add an account manually now? [Y/n]"
#     프롬프트를 띄우고 입력을 기다려 스크립트가 그대로 멈춰버린다. 이 프롬프트는 /dev/tty에
#     직접 출력되기 때문에 2>/dev/null로도 가려지지 않는다. stdin을 막으면 op는 대기 없이
#     즉시 종료코드 1로 실패하고, 아래 안내 루프가 사람이 읽을 수 있는 설명을 대신 보여준다.
inject_zenhub_token() {
  local tok
  op_has_account || return 1
  tok="$(op read --account "$ZENHUB_TOKEN_OP_ACCOUNT" "$ZENHUB_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$tok" ]] || return 1
  strip_zenhub_token_lines
  printf 'export ZENHUB_API_TOKEN=%q\n' "$tok" >> "$HOME/.zshrc"
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
  tok="$(op read --account "$ZENHUB_TOKEN_OP_ACCOUNT" "$JIRA_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$tok" ]] || return 1
  strip_jira_token_lines
  printf 'export JIRA_API_TOKEN=%q\n' "$tok" >> "$HOME/.zshrc"
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
  tok="$(op read --account "$ZENHUB_TOKEN_OP_ACCOUNT" "$SLANG_GPT_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$tok" ]] || return 1
  strip_slang_gpt_token_lines
  printf 'export SLANG_GPT_API_KEY=%q\n' "$tok" >> "$HOME/.zshrc"
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
  email="$(op read --account "$ZENHUB_TOKEN_OP_ACCOUNT" "$DCM_EMAIL_OP_REF" 2>/dev/null </dev/null)" || return 1
  key="$(op read --account "$ZENHUB_TOKEN_OP_ACCOUNT" "$DCM_CI_KEY_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$email" && -n "$key" ]] || return 1   # 둘 다 있어야 주입 (반쪽 인증 방지)
  strip_dcm_token_lines
  printf 'export DCM_EMAIL=%q\n' "$email" >> "$HOME/.zshrc"
  printf 'export DCM_CI_KEY=%q\n' "$key" >> "$HOME/.zshrc"
}

log "ZENHUB_API_TOKEN 주입 (1Password 공용 토큰)"
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
  echo "     [설정 방법 — 1Password 앱에서]"
  echo "       1) 1Password 앱을 열고 팀 계정($ZENHUB_TOKEN_OP_ACCOUNT)으로 로그인"
  echo "       2) 앱 메뉴 > 설정(⌘,) > '개발자' 탭 > '1Password CLI와 통합' 체크"
  echo "          · '개발자' 탭이 안 보이면: 설정 > 보안 > 'Touch ID로 잠금 해제'를 먼저 켜세요"
  echo "          · 터미널을 이미 열어둔 상태였다면 체크 후 이 창에서 Enter만 누르면 됩니다"
  echo ""
  echo "     [잘 됐는지 확인하려면 — 새 터미널 창에서]"
  echo "       op account list   ← 팀 계정($ZENHUB_TOKEN_OP_ACCOUNT)이 목록에 보이면 성공"
  echo "                            · 목록이 비어 있거나 '계정을 추가할까요?'라고 물으면"
  echo "                              위 2번 체크가 아직 안 된 것입니다 (질문에는 n으로 답하세요)"
  echo "                            · 몇 초~수십 초 멈추면 1Password 앱이 잠금 해제(Touch ID)를"
  echo "                              기다리는 중입니다 — 1Password 창에서 승인하면 진행됩니다"
  echo ""
  echo "     ※ 'op account add'를 직접 입력할 필요는 없습니다 — 앱 통합을 켜면 계정이 자동 등록됩니다."
  echo "     ※ 계정 목록에는 보이는데 계속 실패한다면, 팀 'API Token' 금고 접근 권한이 없는 경우입니다."
  echo "        이때는 팀 관리자에게 해당 금고 공유를 요청해 주세요."
  echo ""
}

# 9단계 검증 출력에서 재사용할 op 상태. 여기서 한 번만 판정한다 —
# op 호출은 1Password 앱 승인(Touch ID)을 기다릴 수 있어 검증 단계에서 다시 부르면 또 멈춘다.
#   missing = op 미설치 · not-ready = 설치됐지만 앱 CLI 통합/권한 미완료 · ready = 토큰까지 읽힘
OP_STATUS="missing"

if ! have op; then
  echo "  ⚠ op(1password-cli) 미설치 → ZENHUB_API_TOKEN 수동 설정 필요"
  echo "     (brew install --cask 1password-cli 로 설치한 뒤 './mac-setup.sh --env-only' 를 실행하면 토큰만 다시 주입됩니다)"
elif inject_zenhub_token; then
  OP_STATUS="ready"
  echo "  ✓ ZENHUB_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
elif [[ -t 0 ]]; then
  OP_STATUS="not-ready"
  # 대화형: 1Password 로그인 + CLI 통합을 마칠 때까지 멈춰서 안내 → Enter로 재시도
  while true; do
    print_1password_cli_guide
    printf "     설정을 마쳤으면 Enter(재시도) · 나중에 하려면 s 입력 후 Enter: "
    read -r zh_ans || zh_ans="s"
    if [[ "$zh_ans" == "s" || "$zh_ans" == "S" ]]; then
      echo "  ⚠ ZENHUB_API_TOKEN 주입 건너뜀 → 1Password 설정을 마친 뒤 './mac-setup.sh --env-only' 로 토큰만 다시 주입할 수 있습니다"
      break
    fi
    if inject_zenhub_token; then
      OP_STATUS="ready"
      echo "  ✓ ZENHUB_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
      break
    fi
    # 어느 단계에서 막혔는지 짚어준다 — 계정 자체가 없으면 앱 통합이, 있으면 금고 권한이 원인이다.
    if op_has_account; then
      echo "  ✗ 계정은 등록됐지만 토큰을 읽지 못했습니다."
      echo "     → 팀 계정($ZENHUB_TOKEN_OP_ACCOUNT)으로 로그인된 상태인지, 'API Token' 금고에"
      echo "       접근 권한이 있는지 확인한 뒤 다시 Enter를 누르세요."
    else
      echo "  ✗ 아직 op에 등록된 1Password 계정이 없습니다."
      echo "     → 위 [설정 방법]의 2번('1Password CLI와 통합' 체크)이 켜졌는지 확인한 뒤 다시 Enter를 누르세요."
    fi
  done
else
  # 비대화형(TTY 없음): 멈추지 않고 건너뜀
  OP_STATUS="not-ready"
  echo "  ⚠ op read 실패(비대화형) → 아래 1Password CLI 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 토큰만 자동 주입됩니다"
  echo "     1) 1Password 앱에 팀 계정($ZENHUB_TOKEN_OP_ACCOUNT)으로 로그인"
  echo "     2) 앱 > 설정(⌘,) > 개발자 > '1Password CLI와 통합' 체크"
  echo "     3) 확인: op account list  (팀 계정이 보이면 성공)"
fi

# ------------------------------------------------------------
# 8.6. JIRA_API_TOKEN 주입 (개발팀 공용 계정 Jira 토큰 — 1Password에서 자동 주입)
#   ZenHub와 동일한 방식. op 계정 설정(앱 CLI 통합)은 위 8.5에서 이미 안내·처리됐으므로
#   여기서는 그 안내를 반복하지 않고 '주입 시도 + 원인별 경고'만 한다.
#   자격증명은 개발팀 공용 계정(dev@cocode.im)의 Jira 토큰(팀 "API Token" 볼트 > "Laputa Atlassian API Token" > "Jira API Token" 필드).
#   mcp-atlassian(Docker)이 JIRA_USERNAME+JIRA_API_TOKEN으로 Basic 인증을 내부 처리하므로 raw 토큰만 주입한다.
#   (2026-07 실측: 이 토큰으로 mcp-atlassian 경유 실제 Jira 프로젝트 조회 성공 — Rovo 없이 동작 검증됨.)
# ------------------------------------------------------------
log "JIRA_API_TOKEN 주입 (1Password 공용 계정 Jira 토큰, mcp-atlassian용)"
# 주입 여부는 9단계 검증에서 ~/.zshrc의 JIRA_API_TOKEN 값(JIRA_VAL)으로 직접 판단한다.

# 값이 빈 기존 라인은 먼저 걷어낸다 (ZenHub와 동일 — 빈 값이 남으면 MCP가 '연결됨'처럼 보이며 호출만 실패)
if jira_token_line_is_empty; then
  strip_jira_token_lines
  echo "  · 값이 비어 있던 기존 JIRA_API_TOKEN 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  echo "  ⚠ op(1password-cli) 미설치 → JIRA_API_TOKEN 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './mac-setup.sh --env-only' 실행)"
elif inject_jira_token; then
  echo "  ✓ JIRA_API_TOKEN 주입 완료 (~/.zshrc, 토큰 값은 커밋되지 않음)"
else
  # op가 준비됐는데도 못 읽었다면 대개 팀 'API Token' 볼트 접근 권한이 없거나 항목/필드명이 다른 경우.
  if op_has_account; then
    echo "  ⚠ JIRA_API_TOKEN 미주입 — 1Password에서 'Laputa Atlassian API Token > Jira API Token'을 읽지 못했습니다."
    echo "     확인하세요:"
    echo "       1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    echo "       2) 볼트에 'Laputa Atlassian API Token' 항목 + 'Jira API Token' 필드가 있는지"
    echo "     확인 후 './mac-setup.sh --env-only' 를 실행하면 토큰만 다시 주입됩니다 (그전까지 jira MCP는 미주입 상태)."
  else
    echo "  ⚠ JIRA_API_TOKEN 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM 토큰이 함께 주입됩니다."
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
#     claude mcp 등록 단계가 없다 (그래서 9단계 검증도 'mcp:' 형태가 아닌 단순 주입 여부만 표시).
# ------------------------------------------------------------
log "SLANG_GPT_API_KEY 주입 (1Password 공용 키, slang_gpt 다국어 자동 번역용)"

# 값이 빈 기존 라인은 먼저 걷어낸다 (ZenHub·Jira와 동일 — 빈 값이 남으면 도구가 키를 읽은 것처럼
# 동작하다 호출만 실패한다)
if slang_gpt_token_line_is_empty; then
  strip_slang_gpt_token_lines
  echo "  · 값이 비어 있던 기존 SLANG_GPT_API_KEY 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  echo "  ⚠ op(1password-cli) 미설치 → SLANG_GPT_API_KEY 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './mac-setup.sh --env-only' 실행)"
elif inject_slang_gpt_token; then
  echo "  ✓ SLANG_GPT_API_KEY 주입 완료 (~/.zshrc, 키 값은 커밋되지 않음)"
else
  # op가 준비됐는데도 못 읽었다면 대개 팀 'API Token' 볼트 접근 권한이 없거나 항목/필드명이 다른 경우.
  if op_has_account; then
    echo "  ⚠ SLANG_GPT_API_KEY 미주입 — 1Password에서 'Slang GPT API Token > credential'을 읽지 못했습니다."
    echo "     확인하세요:"
    echo "       1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    echo "       2) 볼트에 'Slang GPT API Token' 항목 + 'credential' 필드가 있는지"
    echo "     확인 후 './mac-setup.sh --env-only' 를 실행하면 키만 다시 주입됩니다 (그전까지 slang_gpt 번역은 사용 불가)."
  else
    echo "  ⚠ SLANG_GPT_API_KEY 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM 토큰이 함께 주입됩니다."
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
#   ZenHub(8.5)·Jira(8.6)·Slang GPT(8.7)와 동일한 방식이며, op 계정 설정(앱 CLI 통합) 안내는
#   8.5에서 이미 처리했으므로 여기서는 반복하지 않고 '주입 시도 + 원인별 경고'만 한다.
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "DCM CI CD"
#       · 사용자명(username) 필드 = DCM_EMAIL(이메일)
#       · 자격 증명(credential) 필드 = DCM_CI_KEY(CI 키)
#   ※ 두 값이 모두 있어야 인증되므로, 하나라도 못 읽으면 아무것도 주입하지 않는다(반쪽 인증 방지).
# ------------------------------------------------------------
log "DCM_EMAIL·DCM_CI_KEY 주입 (1Password 공용 항목 'DCM CI CD', DCM CI 라이선스 인증용)"

# 값이 빈 기존 라인은 먼저 걷어낸다 (다른 토큰과 동일 — 빈 값이 남으면 dcm이 키를 읽은 것처럼
# 동작하다 인증만 조용히 실패한다)
if dcm_token_line_is_empty; then
  strip_dcm_token_lines
  echo "  · 값이 비어 있던 기존 DCM_EMAIL/DCM_CI_KEY 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  echo "  ⚠ op(1password-cli) 미설치 → DCM_EMAIL·DCM_CI_KEY 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './mac-setup.sh --env-only' 실행)"
elif inject_dcm_token; then
  echo "  ✓ DCM_EMAIL·DCM_CI_KEY 주입 완료 (~/.zshrc, 값은 커밋되지 않음)"
else
  # op가 준비됐는데도 못 읽었다면 대개 팀 'API Token' 볼트 접근 권한이 없거나 항목/필드명이 다른 경우.
  if op_has_account; then
    echo "  ⚠ DCM_EMAIL·DCM_CI_KEY 미주입 — 1Password에서 'DCM CI CD'의 사용자명(username)/자격 증명(credential)을 읽지 못했습니다."
    echo "     확인하세요:"
    echo "       1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    echo "       2) 볼트에 'DCM CI CD' 항목 + 사용자명(username)·자격 증명(credential) 필드가 있는지"
    echo "     확인 후 './mac-setup.sh --env-only' 를 실행하면 값만 다시 주입됩니다 (그전까지 DCM CI 인증은 사용 불가)."
  else
    echo "  ⚠ DCM_EMAIL·DCM_CI_KEY 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM 토큰이 함께 주입됩니다."
  fi
fi

# ------------------------------------------------------------
# 8.9. --env-only 마무리: 주입 결과만 요약하고 종료 (아래 9단계 전체 검증은 돌리지 않음)
#   토큰 유무는 9단계와 같은 기준(~/.zshrc의 값)으로 판단한다 — MCP의 'Connected' 표시는
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
  echo "  ZENHUB_API_TOKEN: $([[ -n "$ZH_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  JIRA_API_TOKEN  : $([[ -n "$JIRA_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  SLANG_GPT_API_KEY: $([[ -n "$SLANG_GPT_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo "  DCM_EMAIL/DCM_CI_KEY: $([[ -n "$DCM_EMAIL_VAL" && -n "$DCM_CI_KEY_VAL" ]] && echo '✓ 주입됨' || echo '❌ 미주입 (위 안내 참고)')"
  echo ""
  if [[ -n "$ZH_VAL" || -n "$JIRA_VAL" || -n "$SLANG_GPT_VAL" || ( -n "$DCM_EMAIL_VAL" && -n "$DCM_CI_KEY_VAL" ) ]]; then
    echo "✅ 완료! 새 터미널을 열거나 'source ~/.zshrc' 를 실행한 뒤 claude를 다시 켜세요."
    echo "   (jira MCP는 colima/docker 데몬이 떠 있어야 연결됩니다 — 'colima start')"
  else
    # 하나도 못 넣었으면 '완료' 배너 대신 다음 행동을 알려준다 (종료코드는 전체 설치와 같은 '경고 후 계속' 철학으로 0 유지)
    echo "⚠ 주입된 토큰이 없습니다 — 위 안내(1Password 앱 CLI 통합·금고 권한)를 마친 뒤"
    echo "   './mac-setup.sh --env-only' 를 다시 실행해 주세요."
  fi
  exit 0
fi

# ------------------------------------------------------------
# 9. 검증
# ------------------------------------------------------------
log "설치 검증"
echo "  Xcode.app: $([[ -d /Applications/Xcode.app ]] && echo '✓ 설치됨' || echo '❌ (App Store에서 설치: https://apps.apple.com/app/xcode/id497799835, 또는 mas 로그인 후 재실행)')"
echo "  xcode-select: $(xcode-select -p 2>/dev/null || echo '❌ (Xcode.app 설치 필요 — App Store)')"
echo "  fvm     : $(fvm --version 2>/dev/null || echo '❌')"
echo "  flutter : $(flutter --version 2>/dev/null | head -1 || echo '❌')"
echo "  go      : $(go version 2>/dev/null || echo '❌')"
echo "  python  : $(pyenv exec python --version 2>/dev/null || echo '❌')"
echo "  node    : $(node --version 2>/dev/null || echo '❌')"
echo "  npm     : $(npm --version 2>/dev/null || echo '❌')"
echo "  claude  : $(claude --version 2>/dev/null || echo '❌ (수동 설치: curl -fsSL https://claude.ai/install.sh | bash)')"
echo "  codex   : $(codex --version 2>/dev/null || echo '❌ (수동 설치: brew install --cask codex)')"
# agy는 최초 실행이 대화형 로그인 마법사라, 검증에서는 버전 호출 대신 바이너리 존재만 확인한다.
echo "  agy(antigravity): $(have agy && echo '✓ 설치됨 (최초 실행 시 agy 로 Google 로그인)' || echo '❌ (수동 설치: curl -fsSL https://antigravity.google/cli/install.sh | bash)')"
# ccstatusline: brew formula가 아니라 npx 실행형이라 have로 확인할 수 없다 —
#   ~/.claude/settings.json의 statusLine 키 등록 여부로 판정한다.
echo "  ccstatusline: $(grep -q '\"statusLine\"' "$HOME/.claude/settings.json" 2>/dev/null \
  && echo '✓ 등록됨 (Claude Code에서 적용)' \
  || echo '❌ 미등록 (수동 설정: npx -y ccstatusline@latest)')"
echo "  git email: $(git config --global user.email 2>/dev/null || echo '❌ (git config --global user.email <이메일> 로 설정)')"
echo "  mcp:figma: $(claude plugin list 2>/dev/null | grep -q 'figma@claude-plugins-official' && echo '✓ 설치됨 (/mcp 로그인 필요)' || echo '❌')"
# op는 '설치됨'과 '설정됨(1Password 앱 CLI 통합)'이 다르다 — 설치만 되고 통합이 꺼져 있으면 토큰을 못 읽는다.
# 8.5단계에서 이미 판정한 OP_STATUS를 그대로 쓴다 (여기서 op를 다시 부르면 앱 승인 대기로 멈출 수 있음).
case "${OP_STATUS:-missing}" in
  ready)     echo "  op(1Password CLI): ✓ 설치 + 팀 계정 연결됨" ;;
  # 원인은 두 가지다 — 앱 CLI 통합이 꺼졌거나, 통합은 켰지만 'API Token' 금고 권한이 없거나.
  # 여기서 op를 다시 불러 구분하면 또 멈출 수 있으므로, 확인 순서만 알려준다.
  not-ready)
    echo "  op(1Password CLI): ⚠ 설치됨 (설정 미완료 — 토큰을 읽지 못했습니다)"
    echo "     ① 1Password 앱 > 설정(⌘,) > 개발자 > '1Password CLI와 통합' 체크 확인 → './mac-setup.sh --env-only' 실행"
    echo "     ② 이미 켜져 있다면 팀 'API Token' 금고 접근 권한이 없는 경우입니다 → 팀 관리자에게 공유 요청"
    ;;
  *)         echo "  op(1Password CLI): ❌ (brew install --cask 1password-cli 후 './mac-setup.sh --env-only' 실행)" ;;
esac
ZH_VAL=$(grep '^export ZENHUB_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export ZENHUB_API_TOKEN=//; s/^"//; s/"$//')
# 토큰 유무는 ~/.zshrc 값으로 판단한다. `claude mcp list`의 'Connected'는 서버 연결만 뜻할 뿐
# 인증 성공을 뜻하지 않는다 — 토큰이 비어도 Connected로 보이고 실제 호출만 실패한다.
echo "  mcp:zenhub: $(claude mcp list 2>/dev/null | grep -q '^zenhub' \
  && echo "✓ 등록됨$([[ -n "$ZH_VAL" ]] && echo ' + 토큰 주입됨 (새 터미널에서 적용)' || echo ' (⚠ 토큰 미주입 — 1Password 앱 CLI 통합 후 --env-only 재실행)')" \
  || echo '❌')"
# jira(mcp-atlassian): Docker + Jira REST 직결 — zenhub와 동일 기준으로 등록/주입 상태를 본다.
JIRA_VAL=$(grep '^export JIRA_API_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export JIRA_API_TOKEN=//; s/^"//; s/"$//')
echo "  mcp:mcp-atlassian(jira): $(claude mcp list 2>/dev/null | grep -q '^mcp-atlassian' \
  && echo "✓ 등록됨$([[ -n "$JIRA_VAL" ]] && echo ' + 토큰 주입됨 (새 터미널·docker 실행 중이어야 적용)' || echo ' (⚠ 토큰 미주입 — 1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')" \
  || echo '❌')"
# slang_gpt 키: MCP가 아니라 CLI가 셸 환경변수로 직접 읽는 값이라 등록 여부 없이 주입 여부만 본다.
SLANG_GPT_VAL=$(grep '^export SLANG_GPT_API_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLANG_GPT_API_KEY=//; s/^"//; s/"$//')
echo "  SLANG_GPT_API_KEY: $([[ -n "$SLANG_GPT_VAL" ]] \
  && echo '✓ 주입됨 (새 터미널에서 적용 — slang_gpt 다국어 자동 번역용)' \
  || echo '❌ 미주입 (1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')"
# DCM CI 인증 키: MCP가 아니라 dcm CLI가 셸 환경변수로 직접 읽는 값이라 등록 여부 없이 주입 여부만 본다.
#   이메일+키 두 값이 모두 있어야 인증되므로 둘 다 채워졌을 때만 '주입됨'으로 표시한다.
DCM_EMAIL_VAL=$(grep '^export DCM_EMAIL=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export DCM_EMAIL=//; s/^"//; s/"$//')
DCM_CI_KEY_VAL=$(grep '^export DCM_CI_KEY=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export DCM_CI_KEY=//; s/^"//; s/"$//')
echo "  DCM_EMAIL/DCM_CI_KEY: $([[ -n "$DCM_EMAIL_VAL" && -n "$DCM_CI_KEY_VAL" ]] \
  && echo '✓ 주입됨 (새 터미널에서 적용 — DCM CI 라이선스 인증용)' \
  || echo '❌ 미주입 (1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')"
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
echo "     ↳ 함께 설치된 다른 AI 코딩 CLI도 최초 1회 로그인이 필요합니다: codex(실행: codex, ChatGPT 계정) · agy(실행: agy, Antigravity=Google 계정)"
echo "     ↳ Claude Code 하단 상태줄(모델·비용·컨텍스트·git 상태)은 ccstatusline으로 구성할 수 있습니다 — 대화형 TUI라 자동 설정이 안 되니, \`npx -y ccstatusline@latest\` 실행 후 위젯을 고르고 저장하면 한 번만에 등록됩니다. 되돌리려면 settings.json의 statusLine 키만 지우면 됩니다"
echo "  5. Claude Code에서 /mcp 실행 → figma를 팀 계정으로 OAuth 로그인 (최초 1회)"
echo "     ↳ jira(atlassian)는 더 이상 OAuth 로그인이 필요 없습니다 — zenhub처럼 1Password 팀 공용 토큰으로 인증합니다"
echo "  6. zenhub·jira·slang_gpt·DCM 토큰(1Password CLI): 실행 중 8.5/8.6/8.7/8.8단계에서 설정 안내가 나오면 아래를 마친 뒤 Enter를 누르면 자동 주입됩니다"
echo "     ↳ 1Password 앱 로그인(team-cocodeinc) → 설정(⌘,) > 개발자 > '1Password CLI와 통합' 체크"
echo "       ('개발자' 탭이 없으면 설정 > 보안 > 'Touch ID로 잠금 해제'를 먼저 켜세요)"
echo "       확인: op account list 에 팀 계정이 보이면 성공 · 건너뛰었다면 './mac-setup.sh --env-only' 로 토큰만 다시 주입할 수 있습니다"
echo "     ↳ jira 토큰은 팀 'API Token' 볼트 > 'Laputa Atlassian API Token' > 'Jira API Token' 필드(개발팀 공용 계정"
echo "       dev@cocode.im)에서 읽어 주입됩니다. jira MCP는 sooperset/mcp-atlassian(Docker) — Jira REST 직결(Rovo 우회)"
echo "     ↳ SLANG_GPT_API_KEY(slang_gpt 다국어 자동 번역용)는 같은 볼트 > 'Slang GPT API Token' > 'credential' 필드에서"
echo "       읽어 주입됩니다. MCP가 아니라 slang_gpt CLI가 환경변수로 직접 읽는 값이라 별도 로그인이 없습니다"
echo "     ↳ DCM_EMAIL·DCM_CI_KEY(DCM CI 라이선스 인증용)는 같은 볼트 > 'DCM CI CD' 항목의 사용자명(username)·자격 증명(credential)"
echo "       두 필드에서 읽어 주입됩니다. 이 역시 MCP가 아니라 dcm CLI가 환경변수로 직접 읽는 값이라 별도 로그인이 없습니다"
echo "     ↳ 주입 후에는 반드시 '새 터미널'에서 claude를 실행하세요(그리고 colima/docker 데몬이 떠 있어야 합니다)."
echo "       claude 실행 시점의 환경변수에서 토큰을 읽으므로, 예전 터미널에서 띄운 claude는 토큰을 못 읽습니다."
echo "       (jira MCP가 docker로 뜨므로 'colima start'로 데몬을 먼저 켜 두세요)"
echo "  7. cocode-skills 팀 플러그인이 '❌'이면: gh auth login 후 스크립트 재실행 (사설 레포 접근에 gh 인증 필요)"
echo "  8. flutter-mcp-toolkit을 특정 Flutter 프로젝트에서 쓰려면 해당 프로젝트에서: flutter-mcp-toolkit codegen-init (mcp_toolkit 패키지 추가, 앱별 1회)"
