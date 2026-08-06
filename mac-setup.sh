#!/bin/bash
# ============================================================
# 맥 초기 개발환경 세팅 스크립트
# 전제: 없음 — Homebrew는 이 스크립트가 자동으로 설치한다(0단계).
#       Xcode.app도 1.5단계에서 자동 설치를 시도한다(App Store 로그인 필요).
#
# 실행 (레포를 clone한 경우): chmod +x mac-setup.sh && ./mac-setup.sh
# 실행 (clone 없이 한 줄로):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh)"
#   └ 이 경우 스크립트 파일 하나만 내려오므로, 팀 셸 설정(.zshrc·.p10k.zsh)은
#     0.5단계에서 같은 레포에서 따로 내려받는다.
#   └ 이미 세팅한 맥에서 토큰(환경변수)만 다시 주입하려면: ./mac-setup.sh --env-only
#
# 기존 맥의 테마/설정을 그대로 가져오려면, 기존 맥에서
#   ~/.zshrc, ~/.p10k.zsh
# 를 이 스크립트와 같은 폴더에 복사해 두세요. (있으면 레포 것 대신 그대로 사용)
# ============================================================
set -e

# ------------------------------------------------------------
# 실행 방식 감지 — 파일로 실행했나, curl 원라이너로 실행했나
#
#   파일로 실행하면(./mac-setup.sh · bash mac-setup.sh) BASH_SOURCE[0]에 그 경로가 들어온다.
#   원라이너(/bin/bash -c "$(curl ...)")로 실행하면 **빈 문자열**이 된다.
#
#   [왜 이걸 구분하나 — 예전에 여기서 사고가 났다]
#   빈 문자열을 그대로 dirname에 넘기면 "."이 나오고, 결국 SCRIPT_DIR이 "지금 터미널이 열려
#   있는 폴더"(대개 홈 폴더)로 잡힌다. 홈 폴더에는 보통 .zshrc가 이미 있으므로,
#   8단계가 그 파일을 "스크립트 옆에 사용자가 놓아둔 설정"으로 착각해
#   `cp ~/.zshrc ~/.zshrc`(자기 자신을 자기 위에 복사)를 시도하고,
#   cp가 오류로 끝나면서 set -e에 걸려 스크립트 전체가 거기서 멈춰버렸다.
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
#   (옵션 없음)  : 전체 설치 (0~10단계)
#   --env-only   : 1Password(op)에서 팀 공용 토큰만 다시 읽어 ~/.zshrc에 주입 (8.5~8.9단계만)
#   --perms-only : Orca 전체 디스크 접근 권한 점검·안내만 다시 실행 (9단계만)
#   -h, --help   : 사용법 출력
#   모르는 옵션은 즉시 에러 종료한다 — 오탈자(예: --env-onyl)가 조용히
#   수 분짜리 전체 설치로 이어지는 사고를 막기 위함이다.
# ------------------------------------------------------------
usage() {
  cat <<'USAGE'
사용법: ./mac-setup.sh [옵션]

  (옵션 없음)   co:code 팀 표준 개발환경 전체 설치 (0~10단계)
                Homebrew가 없으면 0단계에서 자동으로 설치합니다.
  --env-only    1Password(op)에서 팀 공용 토큰(ZENHUB_API_TOKEN·JIRA_API_TOKEN·
                SLANG_GPT_API_KEY·DCM_EMAIL·DCM_CI_KEY·SLACK_TEAM_ID·
                SLACK_BOT_TOKEN)만 다시 읽어 ~/.zshrc에
                주입합니다. 앱/도구 설치 단계는 전부 건너뜁니다.
                (토큰이 바뀌었거나, 설치 때 토큰 주입을 건너뛴 경우에 사용)
  --perms-only  Orca의 '전체 디스크 접근 권한'만 다시 점검하고 안내합니다.
                설치·토큰 주입 단계는 전부 건너뜁니다.
                (설치 때 권한 설정을 건너뛰었거나, 권한 창이 계속 뜰 때 사용)
  -h, --help    이 도움말을 표시합니다
USAGE
}

ENV_ONLY=0
PERMS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --env-only)   ENV_ONLY=1 ;;
    --perms-only) PERMS_ONLY=1 ;;
    -h|--help)    usage; exit 0 ;;
    *)
      echo "❌ 알 수 없는 옵션: $arg"
      echo ""
      usage
      exit 1
      ;;
  esac
done

# 두 모드 옵션은 하는 일이 서로 달라 함께 쓰면 어느 쪽을 원한 건지 알 수 없다 — 조용히
# 한쪽만 실행하지 말고 무엇을 골라야 하는지 알려주고 멈춘다.
if (( ENV_ONLY && PERMS_ONLY )); then
  echo "❌ --env-only 와 --perms-only 는 함께 쓸 수 없습니다 (하나씩 따로 실행해 주세요)"
  exit 1
fi

log()  { echo ""; echo "▶ $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 1Password 관련 여러 단계(3.4 GitHub 인증 자동화 · 8.5~8.9 팀 토큰 주입)가 공유하는
# 팀 계정 식별자와 계정 확인 함수. 가장 먼저 쓰는 단계(3.4)보다 앞에 두어야 해서 여기 둔다.
TEAM_OP_ACCOUNT="team-cocodeinc.1password.com"   # 팀 1Password 계정 (비밀 아님)

# op에 쓸 수 있는 계정이 등록돼 있는지 확인. 등록됨 0, 아니면 1.
#   ⚠ `op account list`는 계정이 하나도 없어도 종료코드 0에 빈 목록('[]')만 출력한다.
#     따라서 종료코드가 아니라 '출력 내용'으로 판단해야 한다.
op_has_account() {
  local accounts
  accounts="$(op account list --format=json 2>/dev/null </dev/null)" || return 1
  [[ -n "$accounts" && "$accounts" != "[]" ]]
}

# 모든 y/n 확인 프롬프트 자동 통과
#   아래 0단계(Homebrew 자동 설치)보다 반드시 먼저 내보내야 한다 — Homebrew 공식 설치
#   스크립트가 이 값을 보고 "계속하려면 Enter를 누르세요" 대기를 생략하기 때문이다.
export NONINTERACTIVE=1          # Homebrew 비대화 모드
export CI=true                   # 많은 CLI가 CI 모드에서 프롬프트 생략

# ------------------------------------------------------------
# 0. Homebrew (없으면 자동 설치)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   Homebrew는 맥에서 개발 도구를 내려받아 설치해주는 프로그램이다. 이 스크립트가 까는
#   도구 대부분이 Homebrew를 거쳐 설치된다. 예전에는 팀원이 brew.sh 안내를 보고 직접
#   설치한 뒤에야 이 스크립트를 돌릴 수 있었지만, 이제는 없으면 여기서 알아서 깔고
#   그대로 계속 진행한다. 준비물 없이 이 스크립트 하나로 끝내기 위한 단계다.
#
#   [왜 공식 설치 스크립트를 쓰나]
#   Homebrew는 자기 자신을 brew로 설치할 수 없다. 공식 설치 스크립트가 유일한 표준
#   경로이며, Homebrew가 필요로 하는 Xcode Command Line Tools(컴파일러 등 기본 개발
#   도구)도 이 스크립트가 함께 설치해준다. 설치에 관리자 권한이 필요해서, 실행 중
#   맥 로그인 암호를 한 번 물어볼 수 있다.
#
#   [설치 위치]
#   칩에 따라 다르다 — Apple Silicon은 /opt/homebrew, Intel은 /usr/local.
#   설치 직후에는 아직 PATH에 반영돼 있지 않으므로 shellenv를 즉시 적용해, 이어지는
#   1단계부터 brew를 바로 쓸 수 있게 한다. (~/.zshrc 영구 반영은 8단계에서 처리)
# ------------------------------------------------------------

# Homebrew 경로 잡기 (Apple Silicon / Intel 자동 감지) — 없으면 1을 반환한다.
# 설치 전/후 두 번 호출하므로 함수로 뺐다.
brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    return 1
  fi
}

if brew_shellenv; then
  :   # 이미 설치돼 있으면 경로만 잡고 넘어간다 (멱등)
elif (( ENV_ONLY || PERMS_ONLY )); then
  # --env-only는 op만, --perms-only는 macOS 기본 명령(sqlite3·open)만 쓰므로
  # 둘 다 아무것도 설치하지 않는다 — Homebrew가 없어도 계속 진행한다
  :
else
  log "0. Homebrew 설치"
  echo "  · Homebrew가 없습니다 → 공식 설치 스크립트로 자동 설치합니다"
  echo "  · 설치 중 맥 로그인(관리자) 암호를 한 번 물어볼 수 있습니다"
  echo "  · Xcode Command Line Tools가 없다면 함께 설치되며, 몇 분 걸릴 수 있습니다"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || echo "  ⚠ 설치 스크립트가 오류로 끝났습니다 → 실제 설치 여부를 아래에서 다시 확인합니다"

  # 설치기가 오류를 뱉어도 실제로는 깔렸을 수 있어(마지막 정리 단계만 실패하는 경우 등)
  # 종료 코드가 아니라 brew 실행 파일이 생겼는지로 최종 판정한다.
  if brew_shellenv; then
    echo "  ✓ Homebrew 설치 완료 ($(brew --prefix))"
  else
    # 여기만은 ⚠ 후 계속이 아니라 중단한다 — 이후 단계 대부분이 brew로 설치되므로,
    # 계속 진행해봐야 전부 실패하고 무엇이 원인인지만 알아보기 어려워진다.
    echo ""
    echo "❌ Homebrew 자동 설치에 실패했습니다."
    echo "   이후 단계 대부분이 Homebrew를 필요로 해서 여기서 멈춥니다."
    echo "   https://brew.sh 안내대로 직접 설치하신 뒤 이 스크립트를 다시 실행해 주세요."
    exit 1
  fi
fi

# ------------------------------------------------------------
# 0.5. 팀 셸 설정(.zshrc · .p10k.zsh) 확보
#
#   [왜 필요한가]
#   8단계는 이 스크립트 옆에 있는 .zshrc / .p10k.zsh를 그대로 복사해 팀 공통 셸 설정과
#   터미널 프롬프트 테마를 맞춘다. 그런데 레포를 clone하지 않고 아래처럼 한 줄로 실행하면
#     /bin/bash -c "$(curl -fsSL .../mac-setup.sh)"
#   스크립트 파일 하나만 내려오기 때문에 그 두 파일이 옆에 없다. 그대로 두면 8단계가
#   '기본 설정 생성' 경로로 빠져서, 설치는 성공한 것처럼 보이지만 팀과 다른 셸 환경이
#   만들어진다. → 옆에 없으면 같은 레포에서 직접 내려받아 팀 설정을 그대로 유지한다.
#
#   [둘 다 없을 때만 받는 이유]
#   기존 맥에서 쓰던 .zshrc만 옆에 복사해 두는 사용법(파일 상단 안내)을 존중하기 위함이다.
#   하나라도 옆에 있으면 사용자가 의도적으로 가져온 것으로 보고 건드리지 않는다.
#   단, 원라이너(STANDALONE)에는 '옆 폴더'가 없으므로 이 판단을 아예 하지 않고 항상 받는다 —
#   예전에는 이때 홈 폴더를 옆 폴더로 착각해, 사용자의 기존 ~/.zshrc를 '가져온 설정'으로
#   오인하고 팀 설정을 건너뛰는 문제가 있었다.
#
#   내려받기에 실패해도 중단하지 않는다 — 8단계의 기본 설정 생성 경로로 자연히 넘어간다.
# ------------------------------------------------------------
REPO_RAW_BASE="https://raw.githubusercontent.com/coco-de/co-mac/main"
# 8단계가 참조할 dotfile 위치. 기본은 스크립트 옆이고, 원라이너 실행이면 임시 폴더로 바뀐다.
DOTFILE_DIR="$SCRIPT_DIR"

if (( ! ENV_ONLY && ! PERMS_ONLY )) \
   && { (( STANDALONE )) || [[ ! -f "$SCRIPT_DIR/.zshrc" && ! -f "$SCRIPT_DIR/.p10k.zsh" ]]; }; then
  log "0.5. 팀 셸 설정(.zshrc · .p10k.zsh) 내려받기"
  echo "  · 스크립트 옆에 설정 파일이 없습니다 (clone 없이 한 줄로 실행한 경우) → 레포에서 직접 받습니다"
  DOTFILE_DIR="$(mktemp -d)"
  for dotfile in .zshrc .p10k.zsh; do
    if curl -fsSL "$REPO_RAW_BASE/$dotfile" -o "$DOTFILE_DIR/$dotfile"; then
      echo "  ✓ $dotfile 내려받음"
    else
      rm -f "$DOTFILE_DIR/$dotfile"
      echo "  ⚠ $dotfile 내려받기 실패 → 건너뜀 (8단계에서 기본 설정으로 대체)"
    fi
  done
fi

# ============================================================
# 실행 단계 맵 (섹션 번호는 삽입 이력상 비순차 — 아래가 실제 실행 순서)
#   0.   Homebrew (없으면 공식 설치 스크립트로 자동 설치 · Xcode Command Line Tools 동반
#        설치 · 관리자 암호를 물어볼 수 있음 · 설치 실패 시에만 중단)
#   0.5. 팀 셸 설정(.zshrc·.p10k.zsh) 확보 — 스크립트 옆에 둘 다 없으면 레포에서 내려받기
#        (clone 없이 curl 한 줄로 실행한 경우 · 실패해도 8단계 기본 설정으로 계속)
#   1.   GUI 앱 (brew cask: 개발툴·브라우저·1Password·op 등)
#   1.5. Xcode 설치 확인/자동 설치(mas, App Store 로그인 필요) + 개발자 도구 전환
#        (CLT만 활성화돼 있으면 Xcode.app으로 xcode-select 전환 + 최초 실행 동의,
#        sudo 암호 필요 · TTY에서만 시도)
#   1.6. Chrome/Dia 확장 프로그램 자동 추가 (ZenHub for GitHub, External Extensions
#        드롭인 방식, sudo 필요 · TTY에서만 시도 · Dia는 동작 미보장이라 실패해도 경고 후 계속)
#   2.   Claude Code CLI
#   2.5. Claude MCP (figma 플러그인 + zenhub·jira(mcp-atlassian)·slack 토큰 등록)
#        └ 설정 기록/자체완결 설치라 런타임(node·dart)보다 앞서도 무해.
#          런타임은 새 세션에서 MCP 서버가 실제 뜰 때만 필요 (그땐 스크립트 완료 후).
#   2.6. 다른 AI 코딩 CLI (codex=OpenAI(brew cask) · agy=Google Antigravity(공식 스크립트→~/.local/bin))
#   2.7. Slack CLI (공식 설치 스크립트 → /usr/local/bin 또는 ~/.local/bin)
#   3.   CLI 도구 (brew formulae: go·gh·jq·docker 등)
#   3.2. Git 사용자 이메일 (git config --global user.email, TTY면 입력·s로 건너뜀)
#   3.3. 브라우저 번역 언어 자동 설정 (Chrome·Dia → 한국어로 자동 번역, 영어는 번역 안 함)
#   3.4. GitHub 인증 자동화 (1Password 팀 공용 토큰 → gh auth login + gh auth setup-git,
#        이미 인증돼 있으면 건너뜀 · 아래 3.5·4단계 cob 설치가 이 인증을 그대로 사용)
#   3.5. cocode-skills 팀 플러그인 (사설 레포 install.sh, gh 인증 필요 — 보통 3.4에서 자동 완료)
#   4.   Flutter/Dart(FVM) · Dart 글로벌 · gcloud · DCM · Android SDK/AVD
#        └ cob(co-bricks)도 비공개 레포라 gh 인증 필요 (3.4에서 자동 완료, 안 되면 건너뜀)
#   5.   Python (pyenv)
#   6.   Node.js (nvm)
#   6.5. Claude Code 상태줄 (ccstatusline 먼저 시도 → 대화형이라 자동 등록에 보통 실패 →
#        Awesome CC Statusline(small)로 자동 대체 설치, node 설치 직후에 실행 ·
#        ~/.claude/settings.json 자동 등록)
#   7.   oh-my-zsh + powerlevel10k
#   7.5. Terminal.app 프로필 폰트 자동 적용 (MesloLGS NF, Terminal.app 실행 중일 때만)
#   8.   ~/.zshrc / ~/.p10k.zsh 반영
#   8.5. ZENHUB_API_TOKEN 주입 (1Password op read → .zshrc, TTY면 안내 후 Enter)
#   8.6. JIRA_API_TOKEN 주입 (1Password op read → .zshrc, mcp-atlassian Docker MCP용)
#   8.7. SLANG_GPT_API_KEY 주입 (1Password op read → .zshrc, slang_gpt 다국어 자동 번역용)
#   8.8. DCM_EMAIL·DCM_CI_KEY 주입 (1Password op read → .zshrc, DCM CI 라이선스 인증용)
#   8.9. SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (1Password op read → .zshrc, slack MCP용)
#   9.   앱 권한 — Orca 전체 디스크 접근(Full Disk Access) 점검·안내
#        (TTY면 시스템 설정 창을 열어주고 Enter 대기 · 이미 허용돼 있으면 건너뜀)
#   10.  설치 검증 + 다음 단계 안내
# 공통 규칙: 모든 단계 멱등(이미 설치 시 스킵) · 실패해도 ⚠ 후 계속 · 시크릿 미커밋
# 실행 옵션: 옵션 없음=전체 실행 · --env-only=8.5~8.9(토큰 주입)만 재실행 ·
#            --perms-only=9(앱 권한)만 재실행 · -h/--help=사용법
# ============================================================

# ============================================================
# 9단계(앱 권한) 본체 — Orca 전체 디스크 접근(Full Disk Access)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   Orca는 코딩 에이전트라 워크스페이스와 다른 앱의 설정 폴더를 폭넓게 읽는다. macOS는
#   그런 접근을 개인정보 보호(TCC) 기능으로 막고, 폴더를 읽을 때마다 허용 창을 띄운다.
#   이 창에는 '항상 허용'이 없어서, 허용을 눌러도 그 순간 읽은 폴더 하나만 기록된다.
#   → 다른 앱 폴더를 읽을 때마다 같은 창이 계속 뜬다. 이걸 한 번에 끝내는 유일한 방법이
#     '전체 디스크 접근 권한'을 켜 주는 것이라, 이 단계에서 그 설정 창까지 열어 안내한다.
#
#   [왜 스크립트가 대신 켜주지 못하나]
#   권한 기록(TCC.db)은 SIP(시스템 무결성 보호)로 잠겨 있어, sudo로도 프로그램이 직접
#   쓸 수 없다. 회사 관리 기기라면 MDM의 PPPC 페이로드로 사전 배포할 수 있지만, 개인
#   맥에서는 사용자가 시스템 설정에서 직접 켜는 것이 표준이다. 그래서 이 단계는
#   '상태 조회 + 설정 창 자동 열기 + 안내'까지만 자동화한다.
#
#   [정의를 여기 둔 이유]
#   --perms-only 는 설치 단계를 전부 건너뛰고 이 단계만 실행하므로, 설치 블록보다
#   앞에서 정의돼 있어야 한다. 실제 호출은 (전체 실행 시) 아래 9단계 위치에서 한다.
# ============================================================
ORCA_APP_PATH="/Applications/Orca.app"
ORCA_BUNDLE_ID="com.stablyai.orca"
TCC_SYSTEM_DB="/Library/Application Support/com.apple.TCC/TCC.db"
# 10단계 검증 출력에서 재사용할 권한 상태
#   allowed=허용됨 · denied=거부로 기록됨 · unset=아직 기록 없음 ·
#   unknown=조회 불가(권한 없음이 아니라 '모름') · missing-app=Orca 미설치
ORCA_FDA_STATE="unknown"

# Orca의 전체 디스크 접근 권한 상태를 macOS 권한 기록(TCC.db)에서 조회한다.
#   ⚠ 이 기록 파일 자체가 전체 디스크 접근 대상이라, 스크립트를 실행 중인 터미널에
#     그 권한이 없으면 조회가 실패한다. 새로 세팅한 맥에서는 이게 정상이므로
#     실패를 '권한 없음'으로 단정하지 않고 unknown(모름)으로 돌려준다.
orca_fda_state() {
  local raw
  have sqlite3 || { echo "unknown"; return 0; }
  # 먼저 아주 가벼운 질의로 '읽을 수 있는지'만 본다 — 여기서 실패하면 권한이 아니라 조회 자체가 막힌 것이다.
  sqlite3 "$TCC_SYSTEM_DB" "select count(*) from access;" >/dev/null 2>&1 || { echo "unknown"; return 0; }
  raw=$(sqlite3 "$TCC_SYSTEM_DB" \
    "select auth_value from access where service='kTCCServiceSystemPolicyAllFiles' and client='$ORCA_BUNDLE_ID' order by auth_value desc limit 1;" 2>/dev/null || true)
  case "$raw" in
    2)  echo "allowed" ;;   # 허용
    0)  echo "denied"  ;;   # 거부(사용자가 '허용 안 함'을 눌렀거나 기록이 꼬인 상태)
    *)  echo "unset"   ;;   # 기록 없음(빈 값) · 1=미결정 · 3=제한적 — 어느 쪽이든 다시 켜야 한다
  esac
}

# 이 스크립트가 Orca 안의 터미널에서 실행 중인지 판별한다.
#   맞다면 "지금 Orca를 종료하라"고 안내해선 안 된다 — 스크립트 자신이 함께 죽는다.
running_inside_orca() {
  [[ "${__CFBundleIdentifier:-}" == "$ORCA_BUNDLE_ID" || "${TERM_PROGRAM:-}" == "Orca" ]]
}

# 시스템 설정의 '전체 디스크 접근 권한' 창을 바로 연다.
#   macOS 13(Ventura)부터 설정 앱이 바뀌면서 주소도 달라져, 버전에 따라 나눠 호출한다.
open_fda_settings() {
  local major
  major="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
  if [[ "${major:-0}" =~ ^[0-9]+$ ]] && (( major >= 13 )); then
    open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles" >/dev/null 2>&1
  else
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" >/dev/null 2>&1
  fi
}

print_orca_fda_guide() {
  echo ""
  echo "  ⏸  Orca에 '전체 디스크 접근 권한'을 켜 주세요."
  echo ""
  echo "     [무엇을 하는 건가요?]"
  echo "     Orca는 코딩 에이전트라 작업 폴더와 다른 앱의 설정 폴더를 폭넓게 읽습니다."
  echo "     권한이 없으면 폴더를 하나 읽을 때마다 macOS 허용 창이 반복해서 뜹니다."
  echo "     그 창에는 '항상 허용'이 없어서, 허용을 눌러도 그때 읽은 폴더 하나만 기록됩니다."
  echo "     전체 디스크 접근 권한을 한 번 켜는 것이 이 반복을 끝내는 유일한 방법입니다."
  echo ""
  echo "     [켜는 방법 — 방금 열어드린 시스템 설정 창에서]"
  echo "       1) '개인정보 보호 및 보안 > 전체 디스크 접근 권한' 목록을 봅니다"
  echo "       2) 목록에 Orca가 있으면 → 오른쪽 토글을 켭니다"
  echo "       3) 목록에 없으면 → 왼쪽 아래 '+' 를 눌러 $ORCA_APP_PATH 를 추가합니다"
  echo "          · 함께 열어드린 Finder 창에서 Orca를 목록으로 드래그해도 됩니다"
  echo "          · '+' 를 누르면 암호나 Touch ID를 물어볼 수 있습니다 (정상입니다)"
  echo ""
  echo "     [참고 — 이미 눌렀던 허용/거부 기록을 보고 싶다면]"
  echo "       '개인정보 보호 및 보안 > 파일 및 폴더'에서 Orca 항목을 펼치면 지금까지"
  echo "       허용·거부한 폴더 목록이 보입니다. 실수로 '허용 안 함'을 누른 항목이 있으면"
  echo "       거기서 켜 주면 됩니다."
  echo ""
  echo "     ※ 이 권한은 홈 폴더 전체와 다른 앱의 데이터까지 읽을 수 있는 강한 권한입니다."
  echo "        Orca는 성격상 이 권한이 맞는 도구지만, 무엇을 허용하는지는 알고 계시는 게 좋습니다."
  echo "        (부담스럽다면 s로 건너뛰고 폴더별 허용 창을 그때그때 눌러도 동작은 합니다.)"
  echo ""
}

print_orca_fda_reset_guide() {
  echo ""
  echo "     [권한 기록이 꼬여 창이 계속 뜰 때 — 기록 초기화]"
  echo "       tccutil reset SystemPolicyAllFiles $ORCA_BUNDLE_ID   ← 전체 디스크 접근 기록만 초기화"
  echo "       tccutil reset All $ORCA_BUNDLE_ID                    ← 전부 초기화 (마이크·화면 기록 등도 다시 물어봄)"
  echo "     ※ 스크립트가 대신 실행하지는 않습니다 — 정상적으로 허용해 둔 기록까지 지워질 수 있어"
  echo "        직접 판단해서 실행하시는 편이 안전합니다. 초기화 후에는 위 방법으로 다시 켜 주세요."
}

print_orca_restart_notice() {
  echo ""
  echo "     [마지막 한 단계 — Orca 재시작]"
  echo "     권한은 앱이 '시작하는 시점'에 읽힙니다. 지금 켜져 있는 Orca에는 재시작 전까지 적용되지 않습니다."
  echo "     · 시스템 설정이 '종료 후 다시 열기' 버튼을 띄우면 그 버튼을 누르면 됩니다"
  echo "     · 직접 하려면 Orca에서 ⌘Q (메뉴막대 아이콘까지 완전히 종료) 후 다시 실행하세요"
  if running_inside_orca; then
    echo "     ⚠ 지금 이 스크립트가 Orca 안의 터미널에서 실행 중입니다 — 여기서 Orca를 종료하면"
    echo "        스크립트도 함께 끊깁니다. 재시작은 스크립트가 끝난 뒤에 해주세요."
  fi
}

run_orca_permission_step() {
  log "앱 권한 확인 (Orca 전체 디스크 접근 권한)"

  if [[ ! -d "$ORCA_APP_PATH" ]]; then
    ORCA_FDA_STATE="missing-app"
    echo "  ⚠ $ORCA_APP_PATH 없음 → 건너뜀"
    echo "     (Orca 설치 후 './mac-setup.sh --perms-only' 로 이 단계만 다시 실행할 수 있습니다)"
    return 0
  fi

  ORCA_FDA_STATE="$(orca_fda_state)"

  # 멱등: 이미 허용돼 있으면 아무것도 묻지 않고 넘어간다.
  if [[ "$ORCA_FDA_STATE" == "allowed" ]]; then
    echo "  ✓ Orca 전체 디스크 접근 권한 이미 허용됨 → 건너뜀"
    return 0
  fi

  case "$ORCA_FDA_STATE" in
    denied)
      echo "  ✗ Orca가 '거부'로 기록돼 있습니다 — 켜기 전에 아래 초기화가 필요할 수 있습니다"
      ;;
    unset)
      echo "  · Orca에 전체 디스크 접근 권한이 아직 없습니다"
      ;;
    *)
      echo "  · 현재 권한 상태를 확인할 수 없습니다 — 이 터미널에 전체 디스크 접근 권한이 없어"
      echo "    macOS 권한 기록을 읽지 못한 것이며, 실패가 아니라 '모름'입니다."
      echo "    (이미 켜 두셨다면 아래 안내에서 s 를 눌러 건너뛰셔도 됩니다)"
      ;;
  esac

  # 자동화할 수 있는 부분: 설정 창을 정확한 위치로 열고, 드래그용 Finder 창까지 띄운다.
  #   목록에 추가하고 토글을 켜는 것은 macOS가 사람 손으로만 허용한다.
  open -R "$ORCA_APP_PATH" >/dev/null 2>&1 || true   # Finder에 Orca.app 선택 표시 (드래그 앤 드롭용)
  if open_fda_settings; then
    echo "  · 시스템 설정의 '전체 디스크 접근 권한' 창을 열었습니다"
  else
    echo "  ⚠ 시스템 설정 창을 자동으로 열지 못했습니다 → 직접 여세요:"
    echo "     시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한"
  fi

  print_orca_fda_guide
  if [[ "$ORCA_FDA_STATE" == "denied" ]]; then
    print_orca_fda_reset_guide
  fi

  local fda_ans
  if [[ -t 0 ]]; then
    # 대화형: 권한을 켤 때까지 멈춰서 안내 → Enter로 재확인 (8.5단계 1Password 안내와 같은 패턴)
    while true; do
      printf "     권한을 켜셨으면 Enter(다시 확인) · 나중에 하려면 s 입력 후 Enter: "
      read -r fda_ans || fda_ans="s"
      if [[ "$fda_ans" == "s" || "$fda_ans" == "S" ]]; then
        echo "  ⚠ 전체 디스크 접근 권한 설정 건너뜀"
        echo "     → 나중에 './mac-setup.sh --perms-only' 로 이 안내를 다시 받을 수 있습니다"
        break
      fi
      ORCA_FDA_STATE="$(orca_fda_state)"
      if [[ "$ORCA_FDA_STATE" == "allowed" ]]; then
        echo "  ✓ Orca 전체 디스크 접근 권한 확인됨"
        break
      fi
      if [[ "$ORCA_FDA_STATE" == "unknown" ]]; then
        # 이 터미널에 권한이 없어 확인만 못 하는 상황 — 사용자를 무한히 붙잡지 않는다.
        echo "  · 확인은 못 했습니다(이 터미널에 권한이 없어 조회 불가) — 목록에서 Orca 토글이"
        echo "    켜져 있다면 그대로 진행하셔도 됩니다"
        break
      fi
      echo "  ✗ 아직 허용으로 보이지 않습니다 — 목록에서 Orca 토글이 켜져 있는지 확인 후 다시 Enter"
      echo "     (목록에 Orca가 없다면 '+' 로 $ORCA_APP_PATH 를 먼저 추가해야 합니다)"
    done
  else
    # 비대화형(TTY 없음): 멈추지 않고 건너뜀
    echo "  ⚠ 비대화형 실행이라 여기서 멈추지 않습니다"
    echo "     → 위 안내대로 권한을 켠 뒤 './mac-setup.sh --perms-only' 로 확인해 주세요"
  fi

  print_orca_restart_notice
  return 0
}

# --perms-only: 설치·토큰 주입을 전부 건너뛰고 9단계(앱 권한)만 실행하고 끝낸다.
if (( PERMS_ONLY )); then
  run_orca_permission_step
  echo ""
  echo "✅ 앱 권한 점검 완료 (전체 설치는 옵션 없이 './mac-setup.sh' 실행)"
  exit 0
fi

# ============================================================
# 설치 단계 시작 (1~8단계) — --env-only 실행 시 이 블록 전체를 건너뛴다
#   (--perms-only 는 위에서 9단계만 실행하고 이미 종료했으므로 여기까지 오지 않는다)
#   기존 코드를 옮기지 않고 그대로 감싸기만 했으므로, 블록 안쪽 본문은
#   들여쓰기 없이 유지된다 (짝이 되는 fi는 8.5단계 직전에 있다)
# ============================================================
if (( ! ENV_ONLY )); then

# ------------------------------------------------------------
# 1. GUI 앱 (brew cask)
# ------------------------------------------------------------
log "GUI 앱 설치 (Android Studio, Slack, Figma, Claude Desktop, Chrome, Dia, 1Password, Tailscale, Orca, Lumide, Zed, Rive, Stats) + 1Password CLI(op — 앱이 아닌 터미널 도구)"

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
install_cask rive                   "Rive.app"
# Stats: 메뉴막대에 CPU·메모리·디스크·네트워크 사용량을 띄워 주는 시스템 모니터.
#   설치만으로는 메뉴막대에 나타나지 않고, 최초 1회 직접 실행해야 한다 (마지막 안내 참고).
install_cask stats                  "Stats.app"

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
# 1.6. Chrome/Dia 확장 프로그램 자동 추가 (ZenHub for GitHub)
#   구글이 공식 문서화한 "External Extensions" 드롭인 방식을 쓴다:
#   /Library/Application Support/<브라우저>/External Extensions/<확장ID>.json 파일을
#   심어두면 다음 실행 시 브라우저가 스토어에서 자동으로 받아 설치한다(Preferences를
#   직접 고치는 방식은 브라우저의 변조 감지로 되돌아가므로 이 공식 경로만 동작한다).
#   시스템 폴더(/Library)라 sudo가 필요해 TTY에서만 시도하고, 실패해도 경고 후 계속
#   진행한다. Dia(company.thebrowser.dia)도 크로미움 기반이라 같은 방식을 시도하지만,
#   Arc 계열 제품이라 엔터프라이즈 정책 훅을 의도적으로 막아뒀을 수 있어 실제 설치까지
#   이어진다는 보장은 없다 — 적용 안 돼도 무해하므로 실패로 취급하지 않는다.
# ------------------------------------------------------------
log "Chrome/Dia 확장 프로그램 자동 추가 (ZenHub for GitHub)"

install_external_extension() {
  # $1: 브라우저 표시 이름, $2: /Applications 앱 번들명(존재 확인용),
  # $3: /Library/Application Support 아래 폴더명, $4: 확장 ID
  local name="$1" app_bundle="$2" dir_name="$3" ext_id="$4"
  local target_dir="/Library/Application Support/$dir_name/External Extensions"
  local target_file="$target_dir/$ext_id.json"
  if [[ ! -d "/Applications/$app_bundle" ]]; then
    echo "  · $name 미설치 → 확장 등록 건너뜀"
  elif [[ -f "$target_file" ]]; then
    echo "  ✓ $name: ZenHub for GitHub 확장 이미 등록됨"
  elif [[ -t 0 ]]; then
    if sudo mkdir -p "$target_dir" \
      && echo '{"external_update_url": "https://clients2.google.com/service/update2/crx"}' | sudo tee "$target_file" >/dev/null; then
      echo "  ✓ $name: ZenHub for GitHub 확장 등록 완료 (다음 $name 실행 시 자동 설치됩니다)"
    else
      echo "  ⚠ $name: 확장 등록 실패 → 건너뜀 (수동 설치: https://chromewebstore.google.com/detail/zenhub-for-github/$ext_id)"
    fi
  else
    echo "  ⚠ $name: 비대화형 실행(sudo 불가) → 건너뜀. 수동: sudo mkdir -p \"$target_dir\" && echo '{\"external_update_url\": \"https://clients2.google.com/service/update2/crx\"}' | sudo tee \"$target_file\""
  fi
}

install_external_extension "Chrome" "Google Chrome.app" "Google/Chrome" ogcgkffhplmphkaahpmffcafajaocjbd
install_external_extension "Dia"    "Dia.app"           "Dia"           ogcgkffhplmphkaahpmffcafajaocjbd

# ------------------------------------------------------------
# 1.7. Pretendard 폰트 설치 (9개 스타일)
#   Figma 시안 등 디자인 작업에서 널리 쓰이는 한글 폰트 — 로컬에 없으면 시안과
#   다른 폰트로 대체 렌더링되어 깨져 보인다. brew cask 하나로 9개 굵기
#   (Thin/ExtraLight/Light/Regular/Medium/SemiBold/Bold/ExtraBold/Black)가
#   한 번에 설치된다.
# ------------------------------------------------------------
log "Pretendard 폰트 설치 (9개 스타일: Thin~Black)"
if brew list --cask font-pretendard >/dev/null 2>&1; then
  echo "  ✓ font-pretendard 이미 설치됨 (brew)"
else
  brew install --cask font-pretendard || echo "  ⚠ font-pretendard 설치 실패 → 건너뜀 (수동 설치: brew install --cask font-pretendard)"
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
#     ⚠ 런타임에 colima/docker 데몬이 떠 있어야 이 MCP가 뜬다(팀은 backend 개발로 docker 상시 사용).
#   ※ marionette·dart·figma(serve) MCP 정의는 사설 cocode-skills 플러그인 번들에서 제공됨
#     (coco-de/skills의 install.sh — 아래 3.5단계에서 설치)
# ------------------------------------------------------------
log "Claude Code MCP 설치 (figma 플러그인 + zenhub·jira·slack 토큰 등록)"

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
    && echo "  ✓ slack MCP 등록/갱신 (토큰은 8.9단계에서 1Password 공용 항목으로 주입)" \
    || echo "  ⚠ slack MCP 등록 실패 → 건너뜀"
else
  echo "  ⚠ claude CLI가 없어 MCP 플러그인 설치를 건너뜁니다"
fi

# maestro CLI: 팀 표준 세팅에서 제외됨 → 더 이상 설치하지 않는다.
#   ※ pixel-loop 플러그인에 딸린 maestro MCP는 이 CLI가 있어야 뜨므로, 앞으로는 연결되지 않는다.
#     maestro가 꼭 필요한 사람은 직접 설치하면 된다(curl -Ls https://get.maestro.mobile.dev | bash).
#   예전 버전 스크립트로 세팅한 맥에는 아직 남아 있을 수 있는데, 공식 제거 수단이 없어
#   스크립트가 임의 경로를 지우지 않는다 — 위치만 알려주고 삭제는 본인 판단에 맡긴다.
if have maestro; then
  echo "  · maestro CLI가 아직 남아 있습니다 — 팀 표준에서 빠졌으니 필요 없으면 직접 지워 주세요:"
  echo "      rm -rf \"\$HOME/.maestro\"   (그리고 ~/.zshrc의 .maestro/bin PATH 줄 삭제)"
fi
# marionette_mcp / dart mcp-server 는 4단계(Dart 글로벌 패키지 / FVM)에서 설치됨

# flutter-mcp-toolkit (mcp_flutter): 팀 표준 세팅에서 제외됨 → 더 이상 설치하지 않는다.
#   예전 버전 스크립트로 세팅한 맥에는 아직 남아 있을 수 있어, 재실행하면 아래에서 정리된다.
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
      || echo "  ⚠ flutter-mcp-toolkit 플러그인 제거 실패 → 수동 제거 필요(claude plugin uninstall $FMT_PLUGIN)"
  fi
  # 플러그인을 지워도 마켓플레이스 등록은 남으므로 함께 정리한다 (이 마켓플레이스는 이 도구 전용).
  FMT_MARKET=$(claude plugin marketplace list 2>/dev/null | grep -B1 'Arenukvern/mcp_flutter' | sed -n 's/.*❯ *//p' | head -1)
  if [[ -n "$FMT_MARKET" ]]; then
    claude plugin marketplace remove "$FMT_MARKET" >/dev/null 2>&1 \
      && echo "  · 기존 flutter-mcp-toolkit 마켓플레이스 등록 해제" \
      || echo "  ⚠ flutter-mcp-toolkit 마켓플레이스 해제 실패 → 수동 제거 필요(claude plugin marketplace remove $FMT_MARKET)"
  fi
fi
if have flutter-mcp-toolkit; then
  echo "  · flutter-mcp-toolkit CLI가 아직 남아 있습니다 — 팀 표준에서 빠졌으니 필요 없으면 직접 지워 주세요:"
  echo "      rm -f \"$(command -v flutter-mcp-toolkit)\""
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
# 2.7. Slack CLI (slack)
#   Slack 앱/워크플로 개발용 공식 CLI(slackapi/slack-cli). 공식 설치 스크립트가
#   바이너리를 ~/.slack에 내려받고 /usr/local/bin(쓰기 가능 시) 또는 ~/.local/bin에
#   심볼릭 링크를 건다 — claude/agy와 동일하게 성공 판정은 종료 코드가 아니라
#   바이너리 존재(have slack)로 확인한다. ~/.local/bin은 section 2에서 이미 PATH에 반영됨.
# ------------------------------------------------------------
log "Slack CLI 설치 (공식 설치 스크립트)"
if have slack; then
  echo "  ✓ slack 이미 설치됨"
else
  curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash || true
  if have slack; then
    echo "  ✓ slack 설치 완료 (최초 사용 시 slack login 으로 워크스페이스 인증)"
  else
    echo "  ⚠ slack 설치 실패 → 건너뜀 (수동 설치: curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash)"
  fi
fi

# ------------------------------------------------------------
# 3. CLI 도구 (go, pyenv, nvm, git 등)
# ------------------------------------------------------------
log "CLI 도구 설치 (go, pyenv, nvm, git, cocoapods, lefthook 등)"
# zsh-syntax-highlighting, direnv, openjdk@17: 기존 .zshrc에서 참조하는 도구들
# lefthook: 커밋·푸시 직전에 포맷/린트/테스트를 자동으로 돌려주는 Git 훅 관리자.
#   팀 레포에 lefthook.yml 이 있으면 이 CLI가 깔려 있어야 훅이 동작한다
#   (레포별로 최초 1회 `lefthook install` 필요 — 완료 안내 10번 참고).
FORMULAE=(go pyenv nvm git gh jq cocoapods fastlane awscli colima docker docker-compose zsh-syntax-highlighting direnv openjdk@17 lefthook)
for f in "${FORMULAE[@]}"; do
  # 실패해도 멈추지 않는다 — 하나가 안 깔린다고 나머지 15개까지 못 깔 이유가 없다.
  # (가드가 없으면 set -e 때문에 스크립트 전체가 여기서 종료된다)
  brew list "$f" >/dev/null 2>&1 && echo "  ✓ $f 이미 설치됨" \
    || brew install "$f" || echo "  ⚠ $f 설치 실패 → 건너뜀 (수동 설치: brew install $f)"
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
# 3.3. 브라우저 번역 언어 자동 설정 (Chrome·Dia → 한국어)
#   dia://settings/languages(Chrome은 chrome://settings/languages)에서 매번
#   "Translate into this language: 한국어" + "Never translate: English"를 손으로
#   설정해야 하는 번거로움을 없앤다. Chromium 계열 브라우저는 이 값을 프로필
#   폴더의 Preferences(JSON) 파일에 저장하므로(translate.enabled·
#   translate_recent_target·translate_blocked_languages), jq로 미리 심어둔다.
#   브라우저가 실행 중이면 종료할 때 심어둔 값을 덮어쓸 수 있어 건너뛰고
#   경고만 남긴다. 프로필이 아직 없으면(최초 설치, 한 번도 실행 안 함) Default
#   프로필 폴더를 새로 만들어 심어둔다 — 최초 실행 때 이 파일을 그대로 읽는다.
# ------------------------------------------------------------
log "브라우저 번역 언어 자동 설정 (Chrome·Dia → 한국어로 자동 번역, 영어는 번역 안 함)"

set_translate_ko() {
  # $1: 사람이 읽는 이름, $2: 실행 중인지 확인할 프로세스명, $3: 프로필이 들어있는 상위 폴더
  local name="$1" proc="$2" profiles_dir="$3"
  local prefs="$profiles_dir/Default/Preferences"

  if ! have jq; then
    echo "  ⚠ jq 없음 → $name 번역 언어 자동 설정 건너뜀"
    return
  fi
  if pgrep -x "$proc" >/dev/null 2>&1; then
    echo "  ⚠ $name 실행 중 → 번역 언어 자동 설정 건너뜀 ($name 완전히 종료한 뒤 스크립트를 다시 실행하세요)"
    return
  fi

  mkdir -p "$profiles_dir/Default"
  [[ -f "$prefs" ]] || echo '{}' > "$prefs"

  local tmp
  tmp="$(mktemp)"
  if jq '.translate.enabled = true
         | .translate_recent_target = "ko"
         | .translate_blocked_languages = (((.translate_blocked_languages // []) + ["en"]) | unique)' \
       "$prefs" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv "$tmp" "$prefs"
    echo "  ✓ $name 번역 언어 자동 설정 완료 (한국어로 번역, 영어는 번역 안 함)"
  else
    rm -f "$tmp"
    echo "  ⚠ $name 번역 언어 자동 설정 실패 → 건너뜀 (수동 설정: 브라우저의 언어 설정 페이지에서 직접 지정)"
  fi
}

set_translate_ko "Google Chrome" "Google Chrome" "$HOME/Library/Application Support/Google/Chrome"
set_translate_ko "Dia"           "Dia"           "$HOME/Library/Application Support/Dia/User Data"

# ------------------------------------------------------------
# 3.4. GitHub 인증 자동화 (1Password 팀 공용 토큰 → gh auth login)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   coco-de 조직의 co-bricks·skills 레포는 비공개라서, 바로 아래 3.5단계(cocode-skills)와
#   4단계의 cob(co-bricks) 설치가 GitHub 로그인 없이는 실패한다. 예전에는 사람이 직접
#   'gh auth login'을 실행해야 했는데, 이 단계가 팀 공용 1Password 토큰으로 대신
#   로그인해준다 — ZenHub·Jira 토큰 자동 주입(8.5·8.6단계)과 같은 방식이다.
#
#   [동작 전제]
#   1) op(1password-cli) 설치 + 팀 계정 연결(TEAM_OP_ACCOUNT, 8.5단계와 공유) — 준비가
#      안 됐다면 8.5단계 안내를 먼저 따라 하면 이 단계도 함께 준비된다.
#   2) 1Password 팀 공용 항목: "API Token" 볼트 > "GitHub API Token" > credential 필드
#      (레포 최소 read 권한이면 충분한 Personal Access Token)
#
#   [멱등성]
#   'gh auth login'을 이미 마친 사람(수동이든 이 단계든)은 매번 다시 로그인하지 않고 건너뛴다.
#
#   [준비가 안 됐거나 실패해도]
#   ⚠ 후 계속 진행한다 — 아래 3.5단계와 4단계 cob 설치가 각자 gh 인증 상태를 다시 확인해
#   알맞게 건너뛰므로 전체 설치가 멈추지 않는다.
# ------------------------------------------------------------
log "GitHub 인증 자동화 (1Password → gh auth login)"
GITHUB_TOKEN_OP_REF="op://API Token/GitHub API Token/credential"  # 팀 공용 항목 경로 (토큰 값은 1Password에만 존재)
if have gh && gh auth status >/dev/null 2>&1; then
  echo "  ✓ gh 이미 인증됨 (건너뜀)"
elif have gh && op_has_account; then
  gh_token="$(op read --account "$TEAM_OP_ACCOUNT" "$GITHUB_TOKEN_OP_REF" 2>/dev/null </dev/null)" || gh_token=""
  if [[ -n "$gh_token" ]] \
     && printf '%s' "$gh_token" | gh auth login --hostname github.com --with-token >/dev/null 2>&1 \
     && gh auth setup-git >/dev/null 2>&1; then
    echo "  ✓ 1Password 토큰으로 gh 자동 로그인 완료 (git도 이 인증을 그대로 사용)"
  else
    echo "  ⚠ 1Password에서 GitHub 토큰을 읽지 못했습니다 → 건너뜀 (수동: gh auth login)"
    echo "     ※ 팀 공용 항목이 없다면 1Password 'API Token' 볼트에 'GitHub API Token'(credential 필드,"
    echo "       레포 read 권한 PAT)을 만들어 주세요."
  fi
  unset gh_token
else
  echo "  ⚠ gh 미설치 또는 1Password 계정 미연결 → GitHub 인증 건너뜀 (수동: gh auth login)"
fi

# ------------------------------------------------------------
# 3.5. cocode-skills 팀 플러그인 설치 (사설 레포 coco-de/skills)
#   marionette·dart·figma(serve)·dev-cycle·coui 등 cc-* 플러그인 번들을 설치한다.
#   private 레포라 `claude plugin marketplace add`가 안 되므로 팀 install.sh로 동기화.
#   전제: gh 인증(gh auth login) + jq(위 3단계에서 설치). rsync는 macOS 기본 제공.
#   바로 위 3.4단계가 1Password 토큰으로 gh 자동 로그인을 먼저 시도하므로, 보통은 이
#   단계에 오기 전에 이미 인증돼 있다. 3.4가 실패했거나 건너뛴 경우에만 아래 else로 빠진다.
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
  echo "  ⚠ gh 인증 필요 → 위 3.4단계(1Password 자동 로그인) 확인 또는 'gh auth login' 수동 실행 후"
  echo "     재실행하면 cocode-skills 팀 플러그인이 설치됩니다"
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
yes | fvm install stable || echo "  ⚠ Flutter stable 설치 실패 → 건너뜀 (수동 설치: fvm install stable)"
yes | fvm global stable --force 2>/dev/null || yes | fvm global stable \
  || echo "  ⚠ Flutter stable 글로벌 설정 실패 → 건너뜀 (수동 설정: fvm global stable)"
export PATH="$HOME/fvm/default/bin:$PATH"

# 4-b. Dart 글로벌 패키지 (serverpod_cli, marionette_mcp, mcp_server_dart, flutterfire_cli, cob/co-bricks)
log "Dart 글로벌 패키지 설치"
export PUB_CACHE="$HOME/.pub-cache"
export PATH="$PUB_CACHE/bin:$PATH"
dart pub global activate serverpod_cli 4.0.0-beta.0 || echo "  ⚠ serverpod_cli 설치 실패 → 건너뜀"
dart pub global activate marionette_mcp || echo "  ⚠ marionette_mcp 설치 실패 → 건너뜀"
dart pub global activate mcp_server_dart || echo "  ⚠ mcp_server_dart 설치 실패 → 건너뜀"
# flutterfire_cli: pub.dev 공개 패키지라 cob과 달리 GitHub 인증 없이 바로 설치된다
dart pub global activate flutterfire_cli || echo "  ⚠ flutterfire_cli 설치 실패 → 건너뜀"
# cob(co-bricks)는 비공개 레포라 순수 git 인증이 필요하다 — gh 인증(위 3.4단계에서 1Password로
# 자동 로그인 시도) 상태를 먼저 확인해, 안 돼 있으면 원인을 알 수 있는 안내로 대신한다.
# (인증 없이 그대로 시도하면 git이 사용자 이름/암호를 물어보다 알아보기 어려운 원문 에러로 실패한다.)
if have gh && gh auth status >/dev/null 2>&1; then
  dart pub global activate --source git https://github.com/coco-de/co-bricks.git \
    || echo "  ⚠ cob(co-bricks) 설치 실패 → 건너뜀"
else
  echo "  ⚠ GitHub 인증이 안 돼 있어 cob(co-bricks) 설치를 건너뜁니다"
  echo "     (위 3.4단계 1Password 자동 로그인 실패 또는 gh 미설치 — 수동: gh auth login 후 재실행)"
fi

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
pyenv versions --bare | grep -qx "$LATEST_PY" && echo "  ✓ Python $LATEST_PY 이미 설치됨" \
  || pyenv install "$LATEST_PY" || echo "  ⚠ Python $LATEST_PY 설치 실패 → 건너뜀 (수동 설치: pyenv install $LATEST_PY)"
pyenv global "$LATEST_PY" || echo "  ⚠ Python 기본 버전 지정 실패 → 건너뜀 (수동 설정: pyenv global $LATEST_PY)"

# ------------------------------------------------------------
# 6. Node.js (nvm으로 LTS, npm 포함)
# ------------------------------------------------------------
log "Node.js LTS 설치 (nvm, npm 포함)"
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
# nvm이 안 깔렸으면(3단계 실패) 여기서 멈추지 말고 6단계 전체를 건너뛴다.
# shellcheck disable=SC1091
if source "$(brew --prefix nvm)/nvm.sh" 2>/dev/null; then
  nvm install --lts || echo "  ⚠ Node.js LTS 설치 실패 → 건너뜀 (수동 설치: nvm install --lts)"
  nvm alias default 'lts/*' || echo "  ⚠ Node.js 기본 버전 지정 실패 → 건너뜀 (수동 설정: nvm alias default 'lts/*')"
else
  echo "  ⚠ nvm을 불러오지 못했습니다 → Node.js 설치 건너뜀 (3단계에서 nvm 설치가 실패했을 수 있습니다)"
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
log "Claude Code 상태줄 확인 (ccstatusline 시도 → 실패 시 Awesome CC Statusline(small)로 자동 대체)"

if grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "  ✓ 상태줄 이미 등록됨 (~/.claude/settings.json)"
else
  npx -y ccstatusline@latest </dev/null >/dev/null 2>&1 || true
  if grep -q '"statusLine"' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo "  ✓ 상태줄 등록 완료 (ccstatusline, ~/.claude/settings.json — Claude Code에서 바로 적용)"
  else
    echo "  ↳ ccstatusline은 대화형 TUI라 자동 등록되지 않음 → Awesome CC Statusline(small)로 자동 설치 시도"
    if curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh 2>/dev/null | bash -s -- small >/dev/null 2>&1; then
      echo "  ✓ 상태줄 등록 완료 (Awesome CC Statusline, size: small — ~/.claude/settings.json)"
    else
      echo "  ⚠ 상태줄 자동 등록 실패 → 사람이 직접 설정해야 합니다 (수동 설정: npx -y ccstatusline@latest 또는 curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh | bash -s -- small, 아래 '다음 단계' 참고)"
    fi
  fi
fi

# ------------------------------------------------------------
# 7. oh-my-zsh + powerlevel10k + 플러그인
# ------------------------------------------------------------
log "oh-my-zsh 설치"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    || echo "  ⚠ oh-my-zsh 설치 실패 → 건너뜀 (테마·플러그인도 함께 건너뛸 수 있습니다)"
else
  echo "  ✓ oh-my-zsh 이미 설치됨"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

log "powerlevel10k + 플러그인 설치"
[[ -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] || \
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" \
  || echo "  ⚠ powerlevel10k 내려받기 실패 → 건너뜀 (프롬프트 테마가 적용되지 않습니다)"
[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
  || echo "  ⚠ zsh-autosuggestions 내려받기 실패 → 건너뜀"
[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
  || echo "  ⚠ zsh-syntax-highlighting 내려받기 실패 → 건너뜀"
# 기존 .zshrc가 ~/powerlevel10k 를 직접 source 하므로 동일 경로에도 clone
[[ -d "$HOME/powerlevel10k" ]] || \
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k" \
  || echo "  ⚠ ~/powerlevel10k 내려받기 실패 → 건너뜀 (기존 .zshrc가 이 경로를 참조할 때만 필요)"

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
#    - 옆에 둘 다 없었다면 0.5단계가 레포에서 받아둔 것을 복사 (DOTFILE_DIR가 그쪽을 가리킴)
#    - 그것도 없으면 아래 기본 설정 생성
# ------------------------------------------------------------
log "~/.zshrc 설정"

if copy_dotfile "$DOTFILE_DIR/.p10k.zsh" "$HOME/.p10k.zsh" ".p10k.zsh"; then
  :   # copy_dotfile이 결과 메시지를 직접 출력한다
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

if [[ -f "$DOTFILE_DIR/.zshrc" ]]; then
  # 원본과 대상이 같은 파일이면 복사도 백업도 하지 않는다 — 자기 자신을 자기 위에 복사하면
  # cp가 오류로 끝나고 set -e에 걸려 스크립트가 여기서 멈춰버린다.
  # (아래 호환 패치는 어느 경우든 그대로 적용한다 — 모두 멱등이라 두 번 걸려도 안전하다)
  if [[ "$DOTFILE_DIR/.zshrc" -ef "$HOME/.zshrc" ]]; then
    echo "  ✓ .zshrc 이미 제자리에 있음 (복사 생략)"
  else
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
    cp "$DOTFILE_DIR/.zshrc" "$HOME/.zshrc"
  fi
  # --- 새 맥 호환 패치 ---
  # JAVA_HOME: 버전 하드코딩 경로 → 설치돼 있을 때만 잡도록 교체
  #   openjdk@17 이 아직 안 깔린 맥에서 셸을 열 때마다 에러가 찍히지 않게 존재 확인을 붙인다.
  #   (경로는 brew 규칙상 항상 /opt/homebrew/opt/openjdk@17 이라 brew를 호출할 필요가 없다)
  sed -i '' 's|^export JAVA_HOME=.*openjdk@17.*|[[ -d /opt/homebrew/opt/openjdk@17 ]] \&\& export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"|' "$HOME/.zshrc"
  # 미설치 도구를 무조건 source 하는 라인 → 파일 존재 시에만 source 하도록 가드
  sed -i '' 's|^\. "\$HOME/.local/bin/env"|[[ -f "$HOME/.local/bin/env" ]] \&\& . "$HOME/.local/bin/env"|' "$HOME/.zshrc"
  sed -i '' 's|^eval "\$(direnv hook zsh)"|command -v direnv >/dev/null \&\& eval "$(direnv hook zsh)"|' "$HOME/.zshrc"
  # PATH 중복 증식 방지: 터미널을 중첩해서 열 때마다 같은 경로가 쌓이는 것을 막는다.
  #   예전 맥의 .zshrc를 그대로 가져오는 경우 이 설정이 없어서 셸을 열 때마다 PATH가
  #   10개 이상씩 늘어난다(3단계만 겹쳐도 40개 육박 → 명령 탐색이 느려짐).
  #   이미 있으면 건너뛴다 — 멱등.
  #   (sed 삽입은 구현체마다 문법이 달라 실패하기 쉬우므로, 위 토큰 정리와 같은 임시파일 방식을 쓴다)
  if ! grep -q '^typeset -U path' "$HOME/.zshrc" 2>/dev/null; then
    if {
      echo '# PATH 중복 제거 — 터미널을 중첩해서 열어도 같은 경로가 쌓이지 않게 한다 (mac-setup 자동 추가)'
      echo 'typeset -U path fpath PATH FPATH'
      cat "$HOME/.zshrc"
    } > "$HOME/.zshrc.tmp" 2>/dev/null && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"; then
      echo "  ✓ PATH 중복 제거 설정 추가"
    else
      rm -f "$HOME/.zshrc.tmp"
      echo "  ⚠ PATH 중복 제거 설정 추가 실패 — 무시하고 계속합니다"
    fi
  fi
  echo "  ✓ .zshrc 반영 완료 (덮어썼다면 기존 파일은 백업됨, 새 맥 호환 패치 적용)"
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

fi  # ══ 설치 단계(1~8) 끝 — 여기부터(8.5~8.9 토큰 주입)는 --env-only 실행 시에도 수행된다 ══

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
#   ※ 팀 계정 식별자(TEAM_OP_ACCOUNT)와 op_has_account()는 3.4단계보다 앞서 있어야 해서
#     맨 위(have() 바로 아래)에 정의돼 있다 — 이 단계는 그걸 그대로 재사용한다.
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
SLACK_TEAM_ID_OP_REF="op://API Token/Cocode Slack/SLACK_TEAM_ID"    # 팀 공용 항목의 팀 ID 필드 (값은 1Password에만 존재)
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
inject_zenhub_token() {
  local tok
  op_has_account || return 1
  tok="$(op read --account "$TEAM_OP_ACCOUNT" "$ZENHUB_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
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
  tok="$(op read --account "$TEAM_OP_ACCOUNT" "$JIRA_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
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
  tok="$(op read --account "$TEAM_OP_ACCOUNT" "$SLANG_GPT_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
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
  email="$(op read --account "$TEAM_OP_ACCOUNT" "$DCM_EMAIL_OP_REF" 2>/dev/null </dev/null)" || return 1
  key="$(op read --account "$TEAM_OP_ACCOUNT" "$DCM_CI_KEY_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$email" && -n "$key" ]] || return 1   # 둘 다 있어야 주입 (반쪽 인증 방지)
  strip_dcm_token_lines
  printf 'export DCM_EMAIL=%q\n' "$email" >> "$HOME/.zshrc"
  printf 'export DCM_CI_KEY=%q\n' "$key" >> "$HOME/.zshrc"
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
  bot_token="$(op read --account "$TEAM_OP_ACCOUNT" "$SLACK_BOT_TOKEN_OP_REF" 2>/dev/null </dev/null)" || return 1
  [[ -n "$team_id" && -n "$bot_token" ]] || return 1   # 둘 다 있어야 주입 (반쪽 인증 방지)
  strip_slack_token_lines
  printf 'export SLACK_TEAM_ID=%q\n' "$team_id" >> "$HOME/.zshrc"
  printf 'export SLACK_BOT_TOKEN=%q\n' "$bot_token" >> "$HOME/.zshrc"
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
  echo "       1) 1Password 앱을 열고 팀 계정($TEAM_OP_ACCOUNT)으로 로그인"
  echo "       2) 앱 메뉴 > 설정(⌘,) > '개발자' 탭 > '1Password CLI와 통합' 체크"
  echo "          · '개발자' 탭이 안 보이면: 설정 > 보안 > 'Touch ID로 잠금 해제'를 먼저 켜세요"
  echo "          · 터미널을 이미 열어둔 상태였다면 체크 후 이 창에서 Enter만 누르면 됩니다"
  echo ""
  echo "     [잘 됐는지 확인하려면 — 새 터미널 창에서]"
  echo "       op account list   ← 팀 계정($TEAM_OP_ACCOUNT)이 목록에 보이면 성공"
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

# 10단계 검증 출력에서 재사용할 op 상태. 여기서 한 번만 판정한다 —
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
  echo "  ⚠ op read 실패(비대화형) → 아래 1Password CLI 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 토큰만 자동 주입됩니다"
  echo "     1) 1Password 앱에 팀 계정($TEAM_OP_ACCOUNT)으로 로그인"
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
# 주입 여부는 10단계 검증에서 ~/.zshrc의 JIRA_API_TOKEN 값(JIRA_VAL)으로 직접 판단한다.

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
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
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
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
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
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
  fi
fi

# ------------------------------------------------------------
# 8.9. SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (slack MCP용 팀 공용 토큰 — 1Password에서 자동 주입)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   slack MCP(2.5단계에서 등록)가 Slack 워크스페이스에 접속할 때 쓰는 '팀 ID + 봇 토큰' 한 쌍이
#   필요하다. ZenHub·Jira·Slang GPT·DCM과 똑같이 팀 공용 1Password 금고에서 읽어 ~/.zshrc에 적어준다.
#
#   ZenHub(8.5)·Jira(8.6)·Slang GPT(8.7)·DCM(8.8)과 동일한 방식이며, op 계정 설정(앱 CLI 통합)
#   안내는 8.5에서 이미 처리했으므로 여기서는 반복하지 않고 '주입 시도 + 원인별 경고'만 한다.
#   ※ 팀 공용 1Password 항목: "API Token" 볼트 > "Cocode Slack" > SLACK_TEAM_ID·SLACK_BOT_TOKEN 필드
#   ※ 두 값이 모두 있어야 인증되므로, 하나라도 못 읽으면 아무것도 주입하지 않는다(반쪽 인증 방지, DCM과 동일).
# ------------------------------------------------------------
log "SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (1Password 공용 항목 'Cocode Slack', slack MCP용)"

# 값이 빈 기존 라인은 먼저 걷어낸다 (다른 토큰과 동일 — 빈 값이 남으면 MCP가 '연결됨'처럼 보이며 호출만 실패한다)
if slack_token_line_is_empty; then
  strip_slack_token_lines
  echo "  · 값이 비어 있던 기존 SLACK_TEAM_ID/SLACK_BOT_TOKEN 라인을 제거했습니다 (잘못된 인증 상태 방지)"
fi

if ! have op; then
  echo "  ⚠ op(1password-cli) 미설치 → SLACK_TEAM_ID·SLACK_BOT_TOKEN 미주입 (위 ZenHub 안내와 동일하게 op 설치 후 './mac-setup.sh --env-only' 실행)"
elif inject_slack_token; then
  echo "  ✓ SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 완료 (~/.zshrc, 값은 커밋되지 않음)"
else
  # op가 준비됐는데도 못 읽었다면 대개 팀 'API Token' 볼트 접근 권한이 없거나 항목/필드명이 다른 경우.
  if op_has_account; then
    echo "  ⚠ SLACK_TEAM_ID·SLACK_BOT_TOKEN 미주입 — 1Password에서 'Cocode Slack'의 SLACK_TEAM_ID/SLACK_BOT_TOKEN을 읽지 못했습니다."
    echo "     확인하세요:"
    echo "       1) 팀 'API Token' 볼트 접근 권한이 있는지 (없으면 팀 관리자에게 공유 요청)"
    echo "       2) 볼트에 'Cocode Slack' 항목 + SLACK_TEAM_ID·SLACK_BOT_TOKEN 필드가 있는지"
    echo "     확인 후 './mac-setup.sh --env-only' 를 실행하면 값만 다시 주입됩니다 (그전까지 slack MCP는 미주입 상태)."
  else
    echo "  ⚠ SLACK_TEAM_ID·SLACK_BOT_TOKEN 미주입 — op 계정이 아직 준비되지 않았습니다 (위 8.5 ZenHub 안내 참고)."
    echo "     op(1Password CLI) 설정을 마친 뒤 './mac-setup.sh --env-only' 를 실행하면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다."
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
    echo "   (jira MCP는 colima/docker 데몬이 떠 있어야 연결됩니다 — claude/cld 실행 시 꺼져 있으면 자동으로 'colima start' 시도)"
  else
    # 하나도 못 넣었으면 '완료' 배너 대신 다음 행동을 알려준다 (종료코드는 전체 설치와 같은 '경고 후 계속' 철학으로 0 유지)
    echo "⚠ 주입된 토큰이 없습니다 — 위 안내(1Password 앱 CLI 통합·금고 권한)를 마친 뒤"
    echo "   './mac-setup.sh --env-only' 를 다시 실행해 주세요."
  fi
  exit 0
fi

# ------------------------------------------------------------
# 9. 앱 권한 — Orca 전체 디스크 접근(Full Disk Access)
#   본체(run_orca_permission_step)는 파일 앞부분에 정의돼 있다 — --perms-only 가
#   설치 단계를 건너뛰고 이 단계만 실행할 수 있어야 하기 때문이다.
#   설치가 모두 끝난 뒤에 두는 이유: 권한을 켜면 Orca를 재시작해야 하는데, 설치 도중에
#   Orca를 껐다 켜면(특히 Orca 안 터미널에서 실행 중일 때) 설치가 끊길 수 있다.
# ------------------------------------------------------------
run_orca_permission_step

# ------------------------------------------------------------
# 10. 검증
# ------------------------------------------------------------
log "설치 검증"
echo "  brew    : $(brew --version 2>/dev/null | head -1 || echo '❌ (수동 설치: https://brew.sh)')"
echo "  Xcode.app: $([[ -d /Applications/Xcode.app ]] && echo '✓ 설치됨' || echo '❌ (App Store에서 설치: https://apps.apple.com/app/xcode/id497799835, 또는 mas 로그인 후 재실행)')"
echo "  xcode-select: $(xcode-select -p 2>/dev/null || echo '❌ (Xcode.app 설치 필요 — App Store)')"
# ZenHub for GitHub 확장(External Extensions 드롭인) 등록 여부 — Chrome은 공식 지원,
# Dia는 동작이 보장되지 않아 파일이 없어도 오류가 아니라 "미보장" 문구로만 안내한다.
ZH_EXT_ID="ogcgkffhplmphkaahpmffcafajaocjbd"
echo "  ZenHub 확장(Chrome/Dia): $([[ -f "/Library/Application Support/Google/Chrome/External Extensions/$ZH_EXT_ID.json" ]] && echo 'Chrome ✓' || echo 'Chrome ❌') · $([[ -f "/Library/Application Support/Dia/External Extensions/$ZH_EXT_ID.json" ]] && echo 'Dia ✓' || echo 'Dia ❌(동작 미보장 — 안 되면 수동 설치: https://chromewebstore.google.com/detail/zenhub-for-github/'"$ZH_EXT_ID"')')"
# Stats: 메뉴막대 앱이라 '설치됨'과 '메뉴막대에 보임'이 다르다 — 설치 여부만 확인하고 최초 실행은 마지막 안내로 넘긴다.
echo "  Stats.app: $([[ -d /Applications/Stats.app || -d "$HOME/Applications/Stats.app" ]] && echo '✓ 설치됨 (메뉴막대에 안 보이면 최초 1회 실행 필요)' || echo '❌ (수동 설치: brew install --cask stats)')"
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
echo "  slack   : $(slack --version 2>/dev/null || echo '❌ (수동 설치: curl -fsSL https://downloads.slack-edge.com/slack-cli/install.sh | bash)')"
echo "  lefthook: $(lefthook version 2>/dev/null || echo '❌ (수동 설치: brew install lefthook)')"
# 상태줄(ccstatusline / Awesome CC Statusline): 둘 다 brew formula가 아니라
#   npx/curl 실행형이라 have로 확인할 수 없다 — ~/.claude/settings.json의
#   statusLine 키 등록 여부로 판정한다 (어느 쪽이 등록됐는지는 구분하지 않는다).
echo "  상태줄(statusline): $(grep -q '\"statusLine\"' "$HOME/.claude/settings.json" 2>/dev/null \
  && echo '✓ 등록됨 (Claude Code에서 적용)' \
  || echo '❌ 미등록 (수동 설정: npx -y ccstatusline@latest 또는 curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh | bash -s -- small)')"
echo "  git email: $(git config --global user.email 2>/dev/null || echo '❌ (git config --global user.email <이메일> 로 설정)')"
# GitHub 인증(gh): 3.4단계에서 1Password 토큰으로 자동 로그인을 시도한 결과 — 이게 돼 있어야
# 아래 cocode-skills·cob(co-bricks) 둘 다 설치된다.
echo "  GitHub 인증(gh): $(have gh && gh auth status >/dev/null 2>&1 \
  && echo '✓ 인증됨' \
  || echo '❌ (1Password "API Token" 볼트의 "GitHub API Token" 항목 확인 또는 gh auth login 후 재실행)')"
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
# slack: MCP가 등록됐어도 SLACK_TEAM_ID·SLACK_BOT_TOKEN 둘 다 있어야 실제 호출이 된다 (DCM과 동일 기준).
SLACK_TEAM_ID_VAL=$(grep '^export SLACK_TEAM_ID=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLACK_TEAM_ID=//; s/^"//; s/"$//')
SLACK_BOT_TOKEN_VAL=$(grep '^export SLACK_BOT_TOKEN=' "$HOME/.zshrc" 2>/dev/null | tail -1 | sed 's/^export SLACK_BOT_TOKEN=//; s/^"//; s/"$//')
echo "  mcp:slack: $(claude mcp list 2>/dev/null | grep -q '^slack' \
  && echo "✓ 등록됨$([[ -n "$SLACK_TEAM_ID_VAL" && -n "$SLACK_BOT_TOKEN_VAL" ]] && echo ' + 토큰 주입됨 (새 터미널에서 적용)' || echo ' (⚠ 토큰 미주입 — 1Password 앱 CLI 통합/볼트 권한 확인 후 --env-only 재실행)')" \
  || echo '❌')"
echo "  marionette: $([[ -x "$PUB_CACHE/bin/marionette_mcp" ]] && echo '✓' || echo '❌')"
echo "  mcp_server_dart: $(dart pub global list 2>/dev/null | grep -q '^mcp_server_dart ' && echo '✓' || echo '❌')"
echo "  flutterfire_cli: $(dart pub global list 2>/dev/null | grep -q '^flutterfire_cli ' && echo '✓' || echo '❌')"
echo "  cob(co-bricks): $(dart pub global list 2>/dev/null | grep -q '^cob ' && echo '✓' || echo '❌ (위 GitHub 인증(gh) 확인 후 재실행)')"
CS_COUNT=$(ls -d "$HOME/.claude/plugins/marketplaces/cocode-skills/plugins"/*/ 2>/dev/null | grep -c .)
echo "  cocode-skills: $([[ "$CS_COUNT" -gt 0 ]] && echo "✓ ${CS_COUNT}개 플러그인" || echo '❌ (위 GitHub 인증(gh) 확인 후 재실행)')"
echo "  android : $([[ -x "$ANDROID_HOME/platform-tools/adb" ]] && echo "✓ $ANDROID_HOME" || echo '❌')"
echo "  ndk     : $([[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME:-}" ]] && echo "✓ $ANDROID_NDK_HOME" || echo '❌')"
echo "  avd     : $([[ -n "${AVD_NAME:-}" ]] && "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD_NAME" && echo "✓ $AVD_NAME" || echo '❌')"
# Orca 전체 디스크 접근: 9단계에서 판정한 값을 쓰되, 그 뒤에 권한을 켰을 수도 있으니 한 번 더 조회한다
#   (권한 조회는 파일 읽기 한 번이라 화면을 멈추지 않는다 — op와 달리 승인 대기가 없다).
if [[ "$ORCA_FDA_STATE" != "missing-app" ]]; then ORCA_FDA_STATE="$(orca_fda_state)"; fi
case "$ORCA_FDA_STATE" in
  allowed)     echo "  Orca 전체 디스크 접근: ✓ 허용됨 (Orca를 완전히 종료했다 다시 실행해야 적용됩니다)" ;;
  denied)      echo "  Orca 전체 디스크 접근: ❌ 거부로 기록됨 (tccutil reset SystemPolicyAllFiles $ORCA_BUNDLE_ID 후 './mac-setup.sh --perms-only')" ;;
  unset)       echo "  Orca 전체 디스크 접근: ❌ 미설정 ('./mac-setup.sh --perms-only' 로 설정 창 안내를 다시 받을 수 있습니다)" ;;
  missing-app) echo "  Orca 전체 디스크 접근: — (Orca 미설치)" ;;
  *)           echo "  Orca 전체 디스크 접근: ⚠ 확인 불가 — 이 터미널에 권한이 없어 '조회만' 못 한 것입니다 (시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한에서 Orca 토글로 직접 확인)" ;;
esac

echo ""
echo "✅ 완료! 다음 단계:"
echo "  1. 새 터미널을 열거나: source ~/.zshrc"
echo "  2. Orca를 완전히 종료(⌘Q, 메뉴막대 아이콘까지)했다가 다시 실행하세요"
echo "     ↳ 9단계에서 켠 '전체 디스크 접근 권한'은 앱이 시작하는 시점에 읽히므로, 재시작 전에는 적용되지 않습니다"
echo "     ↳ 권한을 아직 안 켰거나 폴더 허용 창이 계속 뜬다면: ./mac-setup.sh --perms-only (설치는 건너뛰고 권한 안내만 다시 실행)"
echo "  3. p10k 테마 설정이 없다면: p10k configure"
echo "  4. Android Studio 실행 후 flutter doctor (SDK/NDK/AVD는 이미 자동 설치·구성됨)"
echo "  5. Claude Code 로그인: claude"
echo "     ↳ 함께 설치된 다른 AI 코딩 CLI도 최초 1회 로그인이 필요합니다: codex(실행: codex, ChatGPT 계정) · agy(실행: agy, Antigravity=Google 계정)"
echo "     ↳ Slack CLI로 직접 앱을 개발하려면 최초 1회 워크스페이스 로그인이 필요합니다: slack login (slack MCP는 아래 7번의 팀 공용 토큰으로 별도 인증)"
echo "     ↳ Claude Code 하단 상태줄(모델·비용·컨텍스트·git 상태)은 6.5단계에서 이미 자동으로 설정됐을 겁니다 — ccstatusline이 대화형이라 등록에 실패하면 Awesome CC Statusline(size: small)이 자동으로 대신 등록됩니다. 직접 위젯을 골라 커스터마이징하고 싶다면 \`npx -y ccstatusline@latest\`를, 다른 크기로 바꾸고 싶다면 \`curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh | bash -s -- <크기>\`를 실행하면 됩니다(크기: xs/s/m/l/xl). 되돌리려면 settings.json의 statusLine 키만 지우면 됩니다"
echo "  6. Claude Code에서 /mcp 실행 → figma를 팀 계정으로 OAuth 로그인 (최초 1회)"
echo "     ↳ jira(atlassian)는 더 이상 OAuth 로그인이 필요 없습니다 — zenhub처럼 1Password 팀 공용 토큰으로 인증합니다"
echo "  7. zenhub·jira·slang_gpt·DCM·slack 토큰(1Password CLI): 실행 중 8.5/8.6/8.7/8.8/8.9단계에서 설정 안내가 나오면 아래를 마친 뒤 Enter를 누르면 자동 주입됩니다"
echo "     ↳ 1Password 앱 로그인(team-cocodeinc) → 설정(⌘,) > 개발자 > '1Password CLI와 통합' 체크"
echo "       ('개발자' 탭이 없으면 설정 > 보안 > 'Touch ID로 잠금 해제'를 먼저 켜세요)"
echo "       확인: op account list 에 팀 계정이 보이면 성공 · 건너뛰었다면 './mac-setup.sh --env-only' 로 토큰만 다시 주입할 수 있습니다"
echo "     ↳ jira 토큰은 팀 'API Token' 볼트 > 'Laputa Atlassian API Token' > 'Jira API Token' 필드(개발팀 공용 계정"
echo "       dev@cocode.im)에서 읽어 주입됩니다. jira MCP는 sooperset/mcp-atlassian(Docker) — Jira REST 직결(Rovo 우회)"
echo "     ↳ SLANG_GPT_API_KEY(slang_gpt 다국어 자동 번역용)는 같은 볼트 > 'Slang GPT API Token' > 'credential' 필드에서"
echo "       읽어 주입됩니다. MCP가 아니라 slang_gpt CLI가 환경변수로 직접 읽는 값이라 별도 로그인이 없습니다"
echo "     ↳ DCM_EMAIL·DCM_CI_KEY(DCM CI 라이선스 인증용)는 같은 볼트 > 'DCM CI CD' 항목의 사용자명(username)·자격 증명(credential)"
echo "       두 필드에서 읽어 주입됩니다. 이 역시 MCP가 아니라 dcm CLI가 환경변수로 직접 읽는 값이라 별도 로그인이 없습니다"
echo "     ↳ SLACK_TEAM_ID·SLACK_BOT_TOKEN(slack MCP용)은 같은 볼트 > 'Cocode Slack' 항목의 SLACK_TEAM_ID·SLACK_BOT_TOKEN"
echo "       두 필드에서 읽어 주입됩니다. slack MCP는 @modelcontextprotocol/server-slack(npx) — 새 터미널에서 claude 실행 시 적용"
echo "     ↳ 주입 후에는 반드시 '새 터미널'에서 claude를 실행하세요."
echo "       claude 실행 시점의 환경변수에서 토큰을 읽으므로, 예전 터미널에서 띄운 claude는 토큰을 못 읽습니다."
echo "       (jira MCP가 docker로 뜨는데, colima가 꺼져 있으면 새 .zshrc의 claude/cld 함수가 자동으로 'colima start'를 시도합니다 — 최초 콜드 스타트는 수십 초 걸릴 수 있으니 미리 켜두면 더 빠릅니다)"
echo "  8. GitHub 인증(gh)이 '❌'이면 cocode-skills·cob(co-bricks) 둘 다 설치되지 않습니다 (3.4단계에서 시도)"
echo "     ↳ 자동 로그인은 팀 'API Token' 볼트 > 'GitHub API Token' > 'credential' 필드(레포 read 권한 PAT)에서"
echo "       읽어 처리됩니다 — 항목이 없다면 팀 관리자에게 생성을 요청한 뒤 스크립트를 재실행하세요"
echo "     ↳ 그래도 안 되면 수동으로: gh auth login 후 스크립트 재실행"
echo "  9. lefthook(Git 훅)은 레포마다 한 번씩 켜야 합니다 — lefthook.yml 이 있는 프로젝트 폴더에서: lefthook install"
echo "     ↳ 이걸 해야 커밋·푸시할 때 포맷/린트/테스트가 자동으로 돌아갑니다 (설정 파일이 없는 레포에서는 할 일 없음)"
echo " 10. Stats(시스템 모니터)는 최초 1회 직접 실행해야 메뉴막대에 나타납니다: open -a Stats"
echo "     ↳ 실행 후 Stats 설정에서 '로그인 시 시작'을 켜 두면 다음부터는 자동으로 떠 있습니다"
