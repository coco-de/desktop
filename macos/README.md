# 🍎 co-mac

> 새로 받은 맥북 한 대를 명령어 한 줄로 co:code 팀 전체와 똑같은 개발환경으로 만들어주는 스크립트입니다.

[![Platform](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Script](https://img.shields.io/badge/script-Bash-4EAA25?logo=gnubash&logoColor=white)](./mac-setup.sh)
[![Package Manager](https://img.shields.io/badge/package_manager-Homebrew-FBB040?logo=homebrew&logoColor=white)](https://brew.sh)

이 저장소에서 보실 파일은 딱 두 개입니다.

- [`mac-setup.sh`](./mac-setup.sh) — 개발환경을 자동으로 설치해주는 스크립트
- `README.md` — 지금 보고 계신 이 문서

(그 외에 팀 공통 터미널 설정 파일 `.zshrc`·`.p10k.zsh`가 함께 들어 있습니다. 스크립트가 설치 과정에서 알아서 가져다 쓰므로 직접 여실 일은 없습니다.)

## 목차

- [🙋 이런 분들을 위한 레포입니다](#who-is-this-for)
- [🚀 빠른 시작](#quickstart)
- [🧰 우리 팀의 기술 스택](#tech-stack)
- [📦 무엇이 설치되나요](#whats-installed)
- [✅ 설치 후 확인할 것](#after-install)
- [🔒 안전한가요](#is-it-safe)
- [🐛 문제가 생겼나요](#troubleshooting)
- [💬 도움이 필요하신가요](#get-help)

<br>

<a id="who-is-this-for"></a>

## 🙋 이런 분들을 위한 레포입니다

co:code는 엔지니어뿐 아니라 디자이너, PM도 하나의 엔지니어링 조직 아래에서 함께 일합니다. 그래서 **직군과 상관없이, 새로 합류한 모든 팀원이 이 스크립트 하나로 노트북을 세팅**합니다.

"나는 개발자가 아닌데 왜 개발환경 스크립트를 실행하지?" 라는 생각이 드신다면, 이렇게 이해해주시면 됩니다.

- 이 스크립트는 사실 여러 개의 앱과 도구를 하나씩 손으로 내려받아 설치하는 번거로운 과정을, 터미널(글자로 명령을 내리는 화면)에서 대신 자동으로 처리해주는 프로그램일 뿐입니다.
- Slack, Figma, Chrome처럼 직군에 관계없이 매일 쓰는 앱들도 이 스크립트가 함께 설치해 드립니다.
- 팀 전체의 노트북 환경이 같으면, 누가 무엇을 도와줄 때 "제 컴퓨터에서는 되는데요?" 같은 상황 없이 서로 빠르게 도와줄 수 있습니다.
- 프로그래밍을 잘 모르셔도 괜찮습니다. 아래 [빠른 시작](#quickstart)만 따라 하시면 됩니다. 실행 중에는 지금 무엇을 하고 있는지 화면에 계속 안내 문구가 표시됩니다.
- 스크립트 코드는 이 저장소의 [`mac-setup.sh`](./mac-setup.sh) 하나뿐이고, 전체가 공개되어 있어 누구나 열어서 무슨 일을 하는지 읽어볼 수 있습니다.

<br>

<a id="quickstart"></a>

## 🚀 빠른 시작

### 준비물

- **macOS가 설치된 맥북. 이게 전부입니다.**

개발 도구를 미리 깔아둘 필요가 없습니다. 예전에는 Homebrew를 먼저 설치해야 했지만, 지금은 **스크립트가 없으면 알아서 설치**합니다(0단계). Xcode도 마찬가지로 없으면 자동 설치를 시도합니다(App Store 로그인 필요 · 아래 [무엇이 설치되나요](#whats-installed) 참고).

> 💡 **Homebrew가 뭔가요?** macOS에서 개발 도구들을 설치·관리해주는 프로그램입니다. 이 스크립트가 설치하는 대부분의 도구는 Homebrew를 통해 내려받아집니다. 없으면 **공식 설치 스크립트로 자동 설치**되므로 따로 준비하실 필요는 없고, 설치 중에 **맥 로그인(관리자) 암호를 한 번 물어볼 수 있으니** 입력해주세요.

### 실행

터미널을 열고 아래 한 줄을 붙여넣은 뒤 Enter를 누르세요.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh)"
```

레포를 내려받거나 Homebrew를 미리 설치할 필요 없이, 이 한 줄로 전부 진행됩니다.

> 💾 **나중에 `--env-only` 같은 옵션을 쓰실 분은** 스크립트를 파일로 받아 두시면 편합니다. 위 한 줄은 스크립트를 내려받아 바로 실행하고 **파일을 남기지 않기 때문**입니다.
>
> ```bash
> mkdir -p ~/co-mac && curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh -o ~/co-mac/mac-setup.sh && chmod +x ~/co-mac/mac-setup.sh
> ~/co-mac/mac-setup.sh
> ```
>
> 이렇게 두면 이후 `~/co-mac/mac-setup.sh --env-only` 처럼 쓸 수 있습니다. (홈 폴더에 바로 두지 말고 `~/co-mac` 같은 **전용 폴더**에 두세요 — 홈 폴더에 두면 스크립트가 여러분의 기존 `~/.zshrc`를 "직접 가져다 둔 설정"으로 보고 팀 설정을 적용하지 않습니다.)

<details>
<summary>레포를 직접 내려받아 실행하고 싶다면 (스크립트를 먼저 읽어보고 싶은 분)</summary>

<br>

```bash
git clone https://github.com/coco-de/co-mac.git
cd co-mac
chmod +x mac-setup.sh && ./mac-setup.sh
```

결과는 위 한 줄 실행과 같고, 스크립트 파일이 폴더에 남아 있어 나중에 `--env-only` 같은 옵션을 쓰기도 편합니다. 다만 **갓 세팅한 맥에서는 `git clone` 단계에서 macOS가 "명령어 라인 개발자 도구를 설치하겠습니까?" 창을 띄울 수 있어**, 창을 눌러 설치를 마칠 때까지 기다려야 합니다. 위의 한 줄 실행은 그 도구까지 스크립트가 0단계에서 함께 설치하므로 **창을 눌러가며 기다리는 단계가 없습니다** (설치 자체는 몇 분 걸릴 수 있습니다).

</details>

이게 전부입니다. 이후로는 화면에 뜨는 진행 상황(`▶ 단계 이름`)을 지켜보시면 됩니다. 도구별로 이미 설치되어 있으면 `✓`, 새로 설치하면 진행 로그, 일부가 실패해도 `⚠` 표시와 함께 건너뛰고 계속 진행됩니다.

> ⏳ **중간에 한 번 입력을 기다립니다.** 실행 도중 Git 설정 단계(3.2)에서 **커밋에 사용할 회사 이메일**을 물어봅니다. **화면을 켜 두고 가끔 확인해 주세요** — 그 앞의 Xcode 자동 설치가 수십 분까지 걸릴 수 있어서, 질문이 뜨기까지 한참 기다려야 할 수도 있습니다. (이미 설정된 맥이라면 묻지 않고, `s` + Enter로 건너뛸 수도 있습니다.)

> 💡 **이미 세팅한 맥에서 토큰(환경변수)만 다시 받고 싶다면**
>
> ```bash
> ./mac-setup.sh --env-only
> ```
>
> 스크립트 파일이 없다면(한 줄 실행으로 설치한 경우) 아래처럼 옵션을 붙여 그대로 실행해도 됩니다. `--` 는 그 뒤가 옵션이라는 표시라 빼면 안 됩니다.
>
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh)" -- --env-only
> ```
>
> 앱·도구 설치는 전부 건너뛰고, 1Password(`op`)에서 팀 공용 토큰(`ZENHUB_API_TOKEN`·`JIRA_API_TOKEN`·`SLANG_GPT_API_KEY`·`DCM_EMAIL`·`DCM_CI_KEY`·`SLACK_TEAM_ID`·`SLACK_BOT_TOKEN`)만 다시 읽어 `~/.zshrc`에 넣어줍니다. 토큰이 바뀌었거나 설치 때 토큰 주입(8.5~8.9단계)을 건너뛴 경우, 전체 설치를 다시 돌릴 필요 없이 몇 초 만에 끝납니다. 사용법은 `./mac-setup.sh --help`로도 볼 수 있습니다.

> 🎯 **팀 Dart 패키지 목록이 바뀌었거나, 패키지만 최신으로 올리고 싶다면**
>
> ```bash
> ./mac-setup.sh --dart-only
> ```
>
> 스크립트 파일이 없다면 `--env-only`와 같은 방식으로 쓰시면 됩니다.
>
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh)" -- --dart-only
> ```
>
> 앱 설치·토큰 주입·권한 단계는 전부 건너뛰고 **Dart 글로벌 패키지**(`coverage`·`melos`·`mason_cli`·`flutter_gen`·`jaspr_cli`·`serverpod_cli`·`flutterfire_cli`·`marionette_mcp`·`mcp_server_dart`·`cob`)만 다시 설치합니다(4-b단계). 이미 깔린 패키지는 최신으로 다시 활성화되므로 몇 번을 실행해도 안전하고, 끝나면 무엇이 깔렸는지 요약해서 보여줍니다. 단 **Flutter/Dart(fvm)는 이미 설치돼 있어야 합니다** — 없으면 전체 설치를 먼저 하라고 안내하고 멈춥니다. `cob(co-bricks)`은 비공개 레포라 **GitHub 인증이 돼 있을 때만** 설치되고(안 돼 있으면 그 항목만 건너뜁니다), GitHub에서 받아 직접 빌드하므로 이 단계에서만 몇 분 걸릴 수 있습니다(멈춘 게 아니니 기다려 주세요).

> 🔐 **Orca가 폴더 접근 허용 창을 계속 띄운다면**
>
> ```bash
> ./mac-setup.sh --perms-only
> ```
>
> 스크립트 파일이 없다면 `--env-only`와 같은 방식으로 쓰시면 됩니다.
>
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh)" -- --perms-only
> ```
>
> 설치·토큰 주입은 전부 건너뛰고, **Orca의 '전체 디스크 접근 권한'** 상태만 확인해 시스템 설정 창까지 열어 안내해 줍니다(9단계). 이미 켜져 있으면 아무것도 묻지 않고 바로 끝납니다. 자세한 내용은 아래 [🔐 Orca 전체 디스크 접근 권한](#orca-full-disk-access)을 봐주세요.

<details>
<summary>예전에 쓰던 맥이 있다면 (선택 사항)</summary>

<br>

기본적으로는 **팀 공통 터미널 설정**(`.zshrc`·`.p10k.zsh`)이 자동으로 적용됩니다. 저장소에 함께 들어 있고, [빠른 시작](#quickstart)의 한 줄 실행으로 돌리면 스크립트가 저장소에서 알아서 내려받아 씁니다. 따로 하실 일은 없습니다.

예전 맥의 터미널 테마·설정을 **대신** 쓰고 싶다면, 그 맥에서 `~/.zshrc`, `~/.p10k.zsh` 두 파일을 **스크립트가 있는 폴더**에 복사해 둔 뒤 실행하세요. 스크립트는 옆에 있는 파일을 우선하므로, 팀 설정 대신 여러분 것이 그대로 적용됩니다(이 경우 저장소에서 따로 내려받지 않습니다).

> ⚠️ 이 방법은 위 `git clone` 방식처럼 **스크립트가 폴더에 실제로 있을 때만** 쓸 수 있습니다. 한 줄 실행에는 "스크립트가 있는 폴더"라는 게 없어서, 항상 팀 설정이 적용됩니다.
>
> ⚠️ **두 파일을 함께 두세요.** 하나만 두면 나머지 하나는 팀 것도 여러분 것도 아닌 **기본값**이 적용됩니다(예: `.zshrc`만 두면 프롬프트 테마는 p10k 기본값).

⚠️ 예전 `.zshrc`를 가져오실 경우 아래 두 가지를 함께 확인해주세요.

- [보안 안내](#is-it-safe) — 예전 `.zshrc`에 API 키가 평문으로 들어 있을 수 있습니다
- 팀 `.zshrc`에만 있는 편의 기능은 따라오지 않습니다 — **`python`·`adb` 경로 설정**(pyenv·Android SDK)과 **`claude` 실행 시 colima 자동 기동**이 대표적입니다. 각각 아래 [🐳 Jira는 docker(colima) 데몬이 필요합니다](#after-install)와 [설치 후 확인할 것](#after-install)을 참고해 직접 추가하시거나, 팀 설정을 쓰시는 편을 권합니다

</details>

<br>

<a id="tech-stack"></a>

## 🧰 우리 팀의 기술 스택

`mac-setup.sh` 하나로 co:code 팀 전체 노트북에 실제로 세팅되는 앱·CLI·언어 런타임을 한눈에 모았습니다. 아이콘은 대부분 [Simple Icons](https://simpleicons.org)에서 받아 이 저장소의 [`assets/icons/`](./assets/icons)에 함께 보관하고 있습니다. Simple Icons에 없는 앱·도구는 실제 브랜드 아이콘을 받아 사용했고, 공식 브랜드 아이콘이 아직 없는 도구는 이름만 표기했습니다 (자세한 목록은 아래 표 끝의 각주 참고).

<br>

**🍺 패키지 관리자** — 아래 도구 대부분이 이걸 통해 설치됩니다. 없으면 스크립트가 가장 먼저 자동으로 설치합니다.

<table>
<tr>
<td align="center" width="100"><img src="assets/icons/homebrew.svg" width="36" height="36" alt="Homebrew"><br><sub><b>Homebrew</b></sub></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
</tr>
</table>

**🖥 GUI 앱**

<table>
<tr>
<td align="center" width="100"><img src="assets/icons/androidstudio.svg" width="36" height="36" alt="Android Studio"><br><sub><b>Android Studio</b></sub></td>
<td align="center" width="100"><img src="assets/icons/slack.png" width="36" height="36" alt="Slack"><br><sub><b>Slack</b></sub></td>
<td align="center" width="100"><img src="assets/icons/figma.svg" width="36" height="36" alt="Figma"><br><sub><b>Figma</b></sub></td>
<td align="center" width="100"><img src="assets/icons/claude.svg" width="36" height="36" alt="Claude Desktop"><br><sub><b>Claude Desktop</b></sub></td>
<td align="center" width="100"><img src="assets/icons/chrome.svg" width="36" height="36" alt="Google Chrome"><br><sub><b>Google Chrome</b></sub></td>
</tr>
<tr>
<td align="center" width="100"><img src="assets/icons/1password.svg" width="36" height="36" alt="1Password"><br><sub><b>1Password</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dia.png" width="36" height="36" alt="Dia"><br><sub><b>Dia</b></sub></td>
<td align="center" width="100"><img src="assets/icons/tailscale.svg" width="36" height="36" alt="Tailscale"><br><sub><b>Tailscale</b></sub></td>
<td align="center" width="100"><img src="assets/icons/orca.png" width="36" height="36" alt="Orca"><br><sub><b>Orca</b></sub></td>
<td align="center" width="100"><img src="assets/icons/lumide.png" width="36" height="36" alt="Lumide"><br><sub><b>Lumide</b></sub></td>
</tr>
<tr>
<td align="center" width="100"><img src="assets/icons/zed.svg" width="36" height="36" alt="Zed"><br><sub><b>Zed</b></sub></td>
<td align="center" width="100"><img src="assets/icons/rive.svg" width="36" height="36" alt="Rive"><br><sub><b>Rive</b></sub></td>
<td align="center" width="100"><img src="assets/icons/stats.png" width="36" height="36" alt="Stats"><br><sub><b>Stats</b></sub></td>
<td align="center" width="100"><sub><b>Pretendard</b><br>(폰트)</sub></td>
<td align="center" width="100"></td>
</tr>
</table>

**🛠 CLI 도구**

<table>
<tr>
<td align="center" width="100"><img src="assets/icons/go.svg" width="36" height="36" alt="Go"><br><sub><b>go</b></sub></td>
<td align="center" width="100"><sub><b>pyenv</b></sub></td>
<td align="center" width="100"><img src="assets/icons/nvm.svg" width="36" height="36" alt="nvm"><br><sub><b>nvm</b></sub></td>
<td align="center" width="100"><img src="assets/icons/git.svg" width="36" height="36" alt="git"><br><sub><b>git</b></sub></td>
<td align="center" width="100"><img src="assets/icons/github.svg" width="36" height="36" alt="GitHub CLI"><br><sub><b>gh</b></sub></td>
<td align="center" width="100"><img src="assets/icons/cocoapods.svg" width="36" height="36" alt="CocoaPods"><br><sub><b>cocoapods</b></sub></td>
</tr>
<tr>
<td align="center" width="100"><img src="assets/icons/fastlane.svg" width="36" height="36" alt="fastlane"><br><sub><b>fastlane</b></sub></td>
<td align="center" width="100"><sub><b>awscli</b></sub></td>
<td align="center" width="100"><sub><b>colima</b></sub></td>
<td align="center" width="100"><img src="assets/icons/docker.svg" width="36" height="36" alt="docker"><br><sub><b>docker</b></sub></td>
<td align="center" width="100"><img src="assets/icons/docker.svg" width="36" height="36" alt="docker-compose"><br><sub><b>docker-compose</b></sub></td>
<td align="center" width="100"><sub><b>direnv</b></sub></td>
</tr>
<tr>
<td align="center" width="100"><img src="assets/icons/zsh.svg" width="36" height="36" alt="zsh-syntax-highlighting"><br><sub><b>zsh-syntax-<br>highlighting</b></sub></td>
<td align="center" width="100"><img src="assets/icons/openjdk.svg" width="36" height="36" alt="openjdk@17"><br><sub><b>openjdk@17</b></sub></td>
<td align="center" width="100"><img src="assets/icons/claude.svg" width="36" height="36" alt="Claude Code"><br><sub><b>Claude Code</b></sub></td>
<td align="center" width="100"><img src="assets/icons/1password.svg" width="36" height="36" alt="1Password CLI"><br><sub><b>op</b><br>(1Password CLI)</sub></td>
<td align="center" width="100"><img src="assets/icons/codex.png" width="36" height="36" alt="codex"><br><sub><b>codex</b><br>(OpenAI)</sub></td>
<td align="center" width="100"><img src="assets/icons/antigravity.png" width="36" height="36" alt="Antigravity"><br><sub><b>agy</b><br>(Antigravity)</sub></td>
</tr>
<tr>
<td align="center" width="100"><img src="assets/icons/claude.svg" width="36" height="36" alt="ccstatusline"><br><sub><b>ccstatusline</b><br>(상태줄)</sub></td>
<td align="center" width="100"><img src="assets/icons/claude.svg" width="36" height="36" alt="Awesome CC Statusline"><br><sub><b>awesome-<br>statusline</b><br>(상태줄 대체)</sub></td>
<td align="center" width="100"><img src="assets/icons/mas.svg" width="36" height="36" alt="mas"><br><sub><b>mas</b><br>(App Store CLI)</sub></td>
<td align="center" width="100"><img src="assets/icons/slack.png" width="36" height="36" alt="Slack CLI"><br><sub><b>slack</b><br>(Slack CLI)</sub></td>
<td align="center" width="100"><img src="assets/icons/lefthook.svg" width="36" height="36" alt="lefthook"><br><sub><b>lefthook</b><br>(Git 훅)</sub></td>
<td align="center" width="100"><sub><b>jq</b><br>(JSON 처리)</sub></td>
</tr>
<tr>
<td align="center" width="100"><sub><b>maestro</b><br>(모바일 UI 자동화)</sub></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
<td align="center" width="100"></td>
</tr>
</table>

**🐦 Flutter / Dart**

<table>
<tr>
<td align="center" width="100"><img src="assets/icons/flutter.svg" width="36" height="36" alt="fvm"><br><sub><b>fvm</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="DCM"><br><sub><b>DCM</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="serverpod_cli"><br><sub><b>serverpod_cli</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="marionette_mcp"><br><sub><b>marionette_mcp</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="mcp_server_dart"><br><sub><b>mcp_server_dart</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="cob"><br><sub><b>cob</b><br>(co-bricks)</sub></td>
</tr>
<tr>
<td align="center" width="100"><img src="assets/icons/firebase.svg" width="36" height="36" alt="flutterfire_cli"><br><sub><b>flutterfire_cli</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="coverage"><br><sub><b>coverage</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="melos"><br><sub><b>melos</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="mason_cli"><br><sub><b>mason_cli</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="flutter_gen"><br><sub><b>flutter_gen</b></sub></td>
<td align="center" width="100"><img src="assets/icons/dart.svg" width="36" height="36" alt="jaspr_cli"><br><sub><b>jaspr_cli</b></sub></td>
</tr>
</table>

**☁️ 클라우드 / 🐍 언어 런타임**

<table>
<tr>
<td align="center" width="100"><img src="assets/icons/gcloud.svg" width="36" height="36" alt="Google Cloud CLI"><br><sub><b>gcloud</b></sub></td>
<td align="center" width="100"><img src="assets/icons/python.svg" width="36" height="36" alt="Python"><br><sub><b>Python</b></sub></td>
<td align="center" width="100"><img src="assets/icons/nodejs.svg" width="36" height="36" alt="Node.js"><br><sub><b>Node.js</b></sub></td>
<td align="center" width="100"><img src="assets/icons/npm.svg" width="36" height="36" alt="npm"><br><sub><b>npm</b></sub></td>
</tr>
</table>

**💻 터미널 환경**

<table>
<tr>
<td align="center" width="100"><sub><b>oh-my-zsh</b></sub></td>
<td align="center" width="100"><sub><b>powerlevel10k</b></sub></td>
<td align="center" width="100"><img src="assets/icons/zsh.svg" width="36" height="36" alt="zsh-autosuggestions"><br><sub><b>zsh-auto-<br>suggestions</b></sub></td>
<td align="center" width="100"><sub><b>MesloLGS NF</b><br>(폰트)</sub></td>
</tr>
</table>

<br>

<sub>※ Slack · Dia · Orca · Lumide · Stats · codex(OpenAI) · agy(Antigravity)는 Simple Icons에 없어, 실제 브랜드 아이콘(파비콘)을 받아 사용했습니다. awscli, pyenv, colima, direnv, jq, maestro, oh-my-zsh, powerlevel10k, MesloLGS NF, Pretendard는 공식 브랜드 아이콘이 없어 텍스트로만 표기했습니다. DCM · coverage · melos · mason_cli · flutter_gen · jaspr_cli · serverpod_cli · marionette_mcp · mcp_server_dart · cob(co-bricks)는 Dart 생태계 도구라 Dart 아이콘으로 대신 표기했습니다. op(1Password CLI)는 1Password의 커맨드라인 버전이라 1Password 아이콘을 함께 사용했습니다. ccstatusline · awesome-statusline은 둘 다 Claude Code 상태줄 도구라 Claude 아이콘으로 대신 표기했습니다.</sub>

<br>

<a id="whats-installed"></a>

## 📦 무엇이 설치되나요

| 분류 | 항목 |
|---|---|
| 🍺 Homebrew | 맥용 패키지 관리자. 없으면 [공식 설치 스크립트](https://brew.sh)로 자동 설치하고 이어서 진행합니다(0단계 · 관리자 암호를 한 번 물어볼 수 있음). Homebrew가 필요로 하는 **Xcode Command Line Tools**도 이때 함께 설치됩니다. 이미 있으면 건너뜁니다 |
| 🖥 GUI 앱 | Android Studio, Slack, Figma, Claude Desktop, Google Chrome, Dia, 1Password, Tailscale, Orca, Lumide, Zed, Rive, Stats(메뉴막대 시스템 모니터 — 최초 1회 직접 실행 필요), Pretendard 폰트(9개 스타일: Thin~Black) |
| 🍎 Xcode 개발자 도구 | Xcode.app이 없으면 `mas`(App Store CLI)로 자동 설치 시도(App Store 로그인 필요 · 수십 GB라 오래 걸릴 수 있음). Command Line Tools만 활성화돼 있으면(`xcodebuild` "requires Xcode" 에러 원인) `xcode-select`를 Xcode.app으로 자동 전환하고 최초 실행 동의(`xcodebuild -runFirstLaunch`)까지 진행 (sudo 암호 입력 필요) |
| 🧩 브라우저 확장 프로그램 | Chrome·Dia에 [ZenHub for GitHub](https://chromewebstore.google.com/detail/zenhub-for-github/ogcgkffhplmphkaahpmffcafajaocjbd) 확장을 자동 등록(External Extensions 드롭인 방식, sudo 암호 입력 필요) — Dia는 동작이 보장되지 않아 실패해도 경고만 남기고 계속 진행 |
| 🔌 Claude MCP | figma 플러그인 자동 설치 + marionette·dart MCP, zenhub·jira·slack MCP 자동 등록. `ZENHUB_API_TOKEN`·`JIRA_API_TOKEN`·`SLACK_TEAM_ID`·`SLACK_BOT_TOKEN`(팀 공용 토큰)은 1Password CLI(`op`)로 `~/.zshrc`에 자동 주입 — git에 커밋 안 됨 (⚠️ figma는 최초 1회 `/mcp` OAuth 로그인. zenhub·jira·slack은 OAuth 대신 1Password 팀 공용 토큰으로 인증 — 1Password 앱의 CLI 통합만 되면 자동 주입. jira는 `sooperset/mcp-atlassian`(Docker)로 **Jira REST API에 직접** 붙어(개발팀 공용 계정 토큰) 조직 Rovo 권한이 필요 없음 — 런타임에 colima/docker 데몬 필요. slack은 `@modelcontextprotocol/server-slack`(npx)로 뜨며 팀 ID+봇 토큰 두 값이 모두 있어야 인증됨 — [설정 방법](#after-install)) |
| 🔑 팀 공용 토큰 | 위 `ZENHUB_API_TOKEN`·`JIRA_API_TOKEN`·`SLACK_TEAM_ID`·`SLACK_BOT_TOKEN`에 더해, 다국어 자동 번역 도구 `slang_gpt`가 쓰는 `SLANG_GPT_API_KEY`, DCM을 CI 모드로 인증하는 `DCM_EMAIL`·`DCM_CI_KEY`(1Password 항목 `DCM CI CD`의 이메일+키 한 쌍)도 같은 방식(1Password CLI → `~/.zshrc`)으로 자동 주입 — `SLANG_GPT_API_KEY`·`DCM_EMAIL`·`DCM_CI_KEY`는 MCP가 아니라 명령줄 도구가 직접 읽는 값이라 등록·로그인 과정이 없음 ([설정 방법](#after-install)) |
| 🔑 GitHub 인증(gh) | coco-de 조직의 비공개 레포(`co-bricks`·`skills`) 접근용 GitHub 로그인을 팀 공용 1Password 토큰으로 자동 처리(`gh auth login` + `gh auth setup-git`) — 이미 인증돼 있으면 건너뜀. 실패해도 계속 진행하며, 아래 cocode-skills·cob(co-bricks)가 각자 인증 상태를 다시 확인해 건너뜀([설정 방법](#after-install)) |
| 🧩 cocode-skills 팀 플러그인 | 사설 레포 `coco-de/skills`의 `install.sh`로 cc-* 플러그인 번들(marionette·dart·figma·dev-cycle·coui 등) 자동 동기화 (⚠️ GitHub 인증 필요 — 보통 위 단계에서 1Password로 자동 처리되며, 안 됐다면 `gh auth login` 수동 실행 후 재실행) |
| 📱 Android SDK | cmdline-tools, platform-tools, build-tools, platforms, NDK, 에뮬레이터 시스템 이미지, AVD까지 전부 자동 설치·구성 (Android Studio 첫 실행 마법사 불필요) |
| 🛠 CLI 도구 | go, pyenv, nvm, git, gh, jq, cocoapods, fastlane, awscli, colima, docker, docker-compose, zsh-syntax-highlighting, direnv, openjdk@17, lefthook(Git 훅 관리자 — 레포별로 최초 1회 `lefthook install` 필요), Claude Code, ccstatusline(Claude Code 상태줄) → 실패 시 awesome-statusline(size: small)으로 자동 대체, codex, agy(Antigravity CLI), slack(Slack CLI), maestro(모바일 UI 자동화 CLI), op(1Password CLI), mas(App Store CLI — **Xcode.app이 없을 때만** 설치, Xcode 자동 설치용) |
| ✉️ Git 설정 | 커밋에 사용할 회사 이메일을 실행 중에 입력받아 전역 설정(`git config --global user.email`) — 이미 설정돼 있으면 묻지 않고 건너뜀 |
| 🌐 브라우저 번역 언어 | Chrome·Dia의 번역 대상 언어를 한국어로, "번역 안 함" 목록을 영어로 자동 설정(`dia://settings/languages` = `chrome://settings/languages`를 매번 손으로 누를 필요 없음) — 브라우저가 실행 중이면 건너뛰고 경고만 표시 |
| 🐦 Flutter | fvm(버전 관리자)으로 Flutter stable 채널 글로벌 설정, DCM(Dart 코드 품질 검사 도구 — CI 인증 키 `DCM_EMAIL`·`DCM_CI_KEY`는 1Password에서 자동 주입) |
| 🎯 Dart 글로벌 패키지 | coverage, melos, mason_cli, flutter_gen, jaspr_cli, serverpod_cli(pub.dev 최신 베타/RC 버전 자동 조회), flutterfire_cli, marionette_mcp, mcp_server_dart, cob(co-bricks) (⚠️ cob은 비공개 레포라 GitHub 인증 필요 — 보통 위 단계에서 1Password로 자동 처리되며, 안 됐다면 `gh auth login` 수동 실행 후 재실행) · 나중에 이 목록만 다시 깔려면 `./mac-setup.sh --dart-only` |
| ☁️ 클라우드 | Google Cloud CLI (gcloud) |
| 🐍 언어 런타임 | Python 최신 3.x (pyenv), Node.js LTS + npm (nvm) |
| 💻 터미널 환경 | oh-my-zsh, powerlevel10k 테마, zsh-autosuggestions, zsh-syntax-highlighting, MesloLGS NF 폰트 |
| 🔐 앱 권한 | Orca의 **전체 디스크 접근 권한** 상태를 확인해, 아직 없으면 시스템 설정의 해당 창을 자동으로 열고 켜는 방법을 안내 (9단계 · 이미 켜져 있으면 건너뜀). 권한 자체는 macOS가 SIP로 잠가 두어 프로그램이 대신 켤 수 없으므로 마지막 토글은 직접 눌러야 합니다 — [설정 방법](#orca-full-disk-access) |

모든 항목은 이미 설치되어 있으면 건너뛰도록 되어 있어, 스크립트를 여러 번 실행해도 안전합니다.

<details>
<summary>도구별 상세 설명 펼쳐보기 (하나하나 뭔지 궁금하신 분만)</summary>

<br>

**패키지 관리자**

| | 도구 | 용도 |
|---|---|---|
| <img src="assets/icons/homebrew.svg" width="20" height="20"> | Homebrew (`brew`) | macOS용 앱·도구 설치 관리자. 아래 도구 대부분이 `brew`로 설치됩니다. 없으면 스크립트가 0단계에서 공식 설치 스크립트로 자동 설치하며(관리자 암호를 한 번 물어볼 수 있음), Homebrew가 필요로 하는 **Xcode Command Line Tools**도 이때 함께 설치됩니다 |

**GUI 앱 (Homebrew Cask)**

| | 도구 | 용도 |
|---|---|---|
| <img src="assets/icons/androidstudio.svg" width="20" height="20"> | Android Studio | 안드로이드 앱 개발 IDE (Flutter 개발에도 사용) |
| <img src="assets/icons/slack.png" width="20" height="20"> | Slack | 팀 커뮤니케이션 |
| <img src="assets/icons/figma.svg" width="20" height="20"> | Figma | 디자인 툴 |
| <img src="assets/icons/claude.svg" width="20" height="20"> | Claude Desktop | Claude AI 어시스턴트 데스크톱 앱 |
| <img src="assets/icons/chrome.svg" width="20" height="20"> | Google Chrome | 웹 브라우저 |
| <img src="assets/icons/dia.png" width="20" height="20"> | Dia | AI 기반 웹 브라우저 |
| <img src="assets/icons/1password.svg" width="20" height="20"> | 1Password | 비밀번호 관리자 |
| <img src="assets/icons/tailscale.svg" width="20" height="20"> | Tailscale | 팀 내부망 접속용 VPN 메시 네트워크 (메뉴바 앱 + CLI) |
| <img src="assets/icons/orca.png" width="20" height="20"> | Orca | AI 코딩 에이전트 도구 (stablyai/orca 탭) — 설치 후 [전체 디스크 접근 권한](#orca-full-disk-access)을 한 번 켜야 폴더 허용 창이 반복해서 뜨지 않습니다 |
| <img src="assets/icons/lumide.png" width="20" height="20"> | Lumide | 에이전트 네이티브 코드 에디터 IDE ([lumide.dev](https://lumide.dev)) |
| <img src="assets/icons/zed.svg" width="20" height="20"> | Zed | 협업 기능이 내장된 코드 에디터 ([zed.dev](https://zed.dev)) |
| <img src="assets/icons/rive.svg" width="20" height="20"> | Rive | 인터랙티브 애니메이션·모션 그래픽 디자인 툴 ([rive.app](https://rive.app)) |
| <img src="assets/icons/stats.png" width="20" height="20"> | Stats | 메뉴막대에 CPU·메모리·디스크·네트워크 사용량을 보여 주는 시스템 모니터 ([exelban/stats](https://github.com/exelban/stats)) — 설치 후 최초 1회 실행해야 메뉴막대에 나타납니다 |
| | Pretendard (font-pretendard) | Figma 시안 등 디자인 작업에서 널리 쓰이는 한글 폰트. 9개 굵기(Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold, Black)를 한 번에 설치해, 로컬에 폰트가 없어 시안과 다르게 렌더링되는 문제를 막아 줍니다 |

이미 `/Applications`에 앱이 설치되어 있으면 건너뜁니다(Pretendard는 앱이 아닌 폰트라 `brew`에 이미 설치돼 있는지로 판단합니다).

**브라우저 확장 프로그램 자동 등록**

Chrome·Dia 설치 직후, [ZenHub for GitHub](https://chromewebstore.google.com/detail/zenhub-for-github/ogcgkffhplmphkaahpmffcafajaocjbd) 확장을 구글이 공식 문서화한 "External Extensions" 드롭인 방식(`/Library/Application Support/<브라우저>/External Extensions/<확장ID>.json`)으로 자동 등록합니다. 다음에 해당 브라우저를 실행하면 스토어에서 자동으로 받아 설치됩니다. 시스템 폴더에 파일을 심어야 해서 **sudo 암호 입력이 필요**하며(터미널 대화형 실행일 때만 시도), Preferences 파일을 직접 고치는 방식은 브라우저의 변조 감지로 되돌아가기 때문에 이 공식 경로만 사용합니다. Dia는 Chrome과 같은 크로미움 기반이라 동일한 방식을 시도하지만, Arc 계열 제품 특성상 엔터프라이즈 정책 훅이 막혀 있을 수 있어 실제 설치까지 이어진다는 보장은 없습니다 — 적용되지 않아도 오류로 취급하지 않고 조용히 넘어가며, 안 될 경우 위 링크에서 수동으로 추가하면 됩니다.

**Android SDK (자동 설치·구성)**

Android Studio 앱만 설치하면 SDK는 비어 있어서, 원래는 앱을 한 번 실행해 설치 마법사를 직접 눌러가며 구성 요소를 받아야 합니다. 이 스크립트는 `android-commandlinetools`(Homebrew)로 받은 `sdkmanager`/`avdmanager`를 이용해 아래 항목을 전부 커맨드라인에서 자동으로 설치·구성하므로, 그 과정이 필요 없습니다.

| 도구 | 용도 |
|---|---|
| cmdline-tools | Android SDK를 터미널에서 다루는 도구 모음 (`sdkmanager`, `avdmanager`). Homebrew 버전은 부트스트랩으로만 쓰고, 최신 버전을 표준 위치(`$ANDROID_HOME/cmdline-tools/latest`)에 정식 설치합니다 |
| platform-tools | `adb` 등 기기·에뮬레이터와 통신하는 도구 |
| build-tools | 최신 안정 버전을 자동으로 찾아 설치 |
| platforms | 최신 안정 Android API 플랫폼을 자동으로 찾아 설치 |
| NDK | 네이티브(C/C++) 코드가 포함된 안드로이드 빌드에 필요. 최신이 아니라 **Flutter stable이 요구하는 버전으로 고정 설치**합니다 — 목록상의 최신 NDK는 프리뷰(r30-beta 등)라 그대로 깔면 Gradle 빌드에서 버전 불일치가 납니다 (요구 버전을 못 읽으면 검증된 기본값 사용) |
| 에뮬레이터 + 시스템 이미지 | Mac 칩 종류(Apple Silicon/Intel)에 맞는 이미지를 자동 선택해 설치. 최신 platform에는 이미지가 아직 없을 수 있어, 실제 배포된 이미지 중 가장 최신 API 버전을 골라 설치합니다 |
| AVD | 위 시스템 이미지로 `Pixel_6_API_<버전>` 이름의 에뮬레이터를 자동 생성 (이미 있으면 건너뜀) |

> ⚠️ Android 관련 항목은 전용 라이선스 동의(`sdkmanager --licenses`)가 필요한데, 이 스크립트가 자동으로 동의 처리합니다.

**CLI 도구**

| | 도구 | 용도 |
|---|---|---|
| <img src="assets/icons/go.svg" width="20" height="20"> | go | Go 프로그래밍 언어 |
| | pyenv | 여러 Python 버전을 관리하는 도구 |
| <img src="assets/icons/nvm.svg" width="20" height="20"> | nvm | 여러 Node.js 버전을 관리하는 도구 |
| <img src="assets/icons/git.svg" width="20" height="20"> | git | 버전 관리 시스템 |
| <img src="assets/icons/github.svg" width="20" height="20"> | gh | GitHub를 터미널에서 다루는 도구. coco-de 비공개 레포(co-bricks·skills) 접근에 필요한 로그인은 팀 공용 1Password 토큰으로 자동 처리됩니다(`gh auth login` + `gh auth setup-git`) — 안 되면 `gh auth login`으로 직접 로그인 |
| <img src="assets/icons/cocoapods.svg" width="20" height="20"> | cocoapods | iOS 라이브러리 의존성 관리자 |
| <img src="assets/icons/fastlane.svg" width="20" height="20"> | fastlane | 앱 빌드·배포 자동화 도구 |
| | awscli | AWS(아마존 클라우드)를 터미널에서 다루는 도구 |
| | colima | Docker Desktop 없이 가볍게 컨테이너를 실행하는 도구 |
| <img src="assets/icons/docker.svg" width="20" height="20"> | docker / docker-compose | 컨테이너 실행 및 관리 CLI (colima와 함께 사용) |
| <img src="assets/icons/zsh.svg" width="20" height="20"> | zsh-syntax-highlighting | 터미널 명령어에 색을 입혀 오타를 줄여주는 플러그인 |
| | direnv | 폴더별로 필요한 환경 변수를 자동으로 불러와 주는 도구 |
| <img src="assets/icons/openjdk.svg" width="20" height="20"> | openjdk@17 | 자바 17 (Android 빌드에 필요) |
| | jq | JSON 형식의 데이터를 터미널에서 다루는 도구. 눈에 잘 안 띄지만 이 스크립트가 여러 곳에서 씁니다 — 브라우저 번역 언어 자동 설정(3.3단계), 팀 플러그인 설치(3.5단계), 상태줄 등록(6.5단계) |
| | maestro | 모바일 앱 화면을 자동으로 조작·촬영하는 CLI. Claude Code의 pixel-loop MCP가 이 도구를 통해 실행 중인 앱 화면을 확인합니다 (공식 설치 스크립트 `get.maestro.mobile.dev`로 설치) |
| <img src="assets/icons/lefthook.svg" width="20" height="20"> | lefthook | 커밋·푸시하기 직전에 코드 정리·검사·테스트를 자동으로 돌려주는 **Git 훅 관리자**([evilmartians/lefthook](https://github.com/evilmartians/lefthook)). 실수로 형식이 어긋나거나 깨진 코드가 올라가는 걸 미리 막아 줍니다. 이 스크립트는 도구만 설치하며, 실제로 켜는 건 레포마다 한 번씩입니다 — `lefthook.yml`이 있는 프로젝트 폴더에서 `lefthook install`을 실행하세요(설정 파일이 없는 레포에서는 할 일 없음) |
| <img src="assets/icons/claude.svg" width="20" height="20"> | Claude Code | 터미널에서 대화하듯 코드를 작성·수정하는 Claude CLI (공식 설치 스크립트 `claude.ai/install.sh`로 설치, `~/.local/bin`) |
| <img src="assets/icons/claude.svg" width="20" height="20"> | ccstatusline | Claude Code 하단 상태줄을 모델·세션 비용·컨텍스트 사용량·git 상태까지 보여주는 두 줄짜리 정보 표시줄로 바꿔 주는 대화형 TUI 도구입니다([sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)). 별도 설치가 필요 없고 `npx -y ccstatusline@latest`로 그때그때 실행하며(Node.js 필요), 뜨는 화면에서 위젯을 고르고 저장하면 `~/.claude/settings.json`에 자동 등록됩니다. 대화형 도구라 이 스크립트에서는 자동 등록되지 않는 경우가 대부분이며, 그때는 아래 awesome-statusline이 자동으로 대신 설치됩니다 |
| <img src="assets/icons/claude.svg" width="20" height="20"> | awesome-statusline | ccstatusline이 대화형이라 자동 등록에 실패했을 때 대신 설치되는 상태줄 도구입니다([AwesomeJun/CC-statusline](https://github.com/AwesomeJun/CC-statusline)). 크기를 인자로 주면(`curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh \| bash -s -- small`) 완전 비대화형으로 설치되어 `~/.claude/settings.json`에 바로 등록됩니다. 이 스크립트는 크기 `small`로 자동 설치합니다 — 다른 크기(xs/s/m/l/xl)를 원하면 위 명령의 마지막 인자만 바꿔 다시 실행하면 됩니다 |
| <img src="assets/icons/codex.png" width="20" height="20"> | codex | OpenAI의 터미널 AI 코딩 에이전트. `brew install --cask codex`로 설치하며, 처음 실행할 때 ChatGPT 계정으로 로그인합니다 |
| <img src="assets/icons/antigravity.png" width="20" height="20"> | agy (Antigravity CLI) | Google의 터미널 AI 코딩 에이전트. 은퇴한 Gemini CLI의 공식 후속 도구로, 단일 실행 파일이라 Claude Code처럼 공식 설치 스크립트(`antigravity.google/cli/install.sh`)로 `~/.local/bin/agy`에 설치합니다(별도 런타임 불필요). 처음 실행할 때 Google 계정으로 로그인합니다 |
| <img src="assets/icons/slack.png" width="20" height="20"> | slack (Slack CLI) | Slack 앱/워크플로 개발용 공식 CLI. 공식 설치 스크립트(`downloads.slack-edge.com/slack-cli/install.sh`)로 `/usr/local/bin` 또는 `~/.local/bin`에 설치합니다. Slack CLI로 직접 앱을 만들려면 처음 한 번 `slack login`으로 워크스페이스 인증이 필요합니다(별개로, Claude Code의 `slack` MCP는 아래 팀 공용 토큰으로 인증됩니다) |
| <img src="assets/icons/1password.svg" width="20" height="20"> | op (1Password CLI) | 1Password 금고를 **터미널에서** 열어보는 명령. 1Password 앱과 같은 금고를 보며, 앱에 로그인해 둔 상태를 그대로 빌려 씁니다. 이 스크립트는 팀 공용 ZenHub·Jira·Slack 토큰을 금고에서 읽어 `~/.zshrc`에 자동으로 넣어주고, GitHub PAT로 `gh auth login`까지 대신 처리하는 데 사용합니다 (설정 방법은 아래 [ZenHub·Jira·Slang GPT·DCM·Slack 토큰 · 1Password CLI 설정](#after-install) 참고) |
| <img src="assets/icons/mas.svg" width="20" height="20"> | mas (App Store CLI) | 터미널에서 Mac App Store 앱을 설치하는 도구. Xcode.app을 자동으로 깔기 위해서만 쓰기 때문에, **Xcode.app이 이미 있으면 mas 자체를 설치하지 않고 건너뜁니다** — App Store에 Apple ID로 로그인이 돼 있어야 하며, 로그인 자체는 mas가 대신 해줄 수 없습니다(로그인 안 돼 있으면 건너뛰고 App Store에서 직접 설치하라고 안내) |

**Flutter / Dart**

| | 도구 | 용도 |
|---|---|---|
| <img src="assets/icons/flutter.svg" width="20" height="20"> | fvm | Flutter 버전 관리자. `fvm global stable`로 stable 채널을 글로벌 설정 |
| <img src="assets/icons/dart.svg" width="20" height="20"> | DCM (Dart Code Metrics) | Dart 코드 품질 검사 도구. CI/자동화 모드 인증에 쓰는 이메일+키(`DCM_EMAIL`·`DCM_CI_KEY`)는 팀 공용 1Password 항목 `DCM CI CD`에서 자동 주입됩니다 |
| <img src="assets/icons/dart.svg" width="20" height="20"> | coverage | 테스트가 코드의 어느 부분까지 확인했는지(커버리지)를 측정해 리포트로 만들어 줍니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | melos | 여러 패키지를 한 레포에 담은 프로젝트(모노레포)의 의존성 설치·스크립트 실행을 한 번에 처리해 줍니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | mason_cli | 미리 만들어 둔 코드 템플릿(brick)으로 새 화면·기능의 뼈대를 찍어내는 도구. 아래 `cob(co-bricks)`이 이 위에서 동작합니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | flutter_gen | 이미지·폰트 같은 파일과 색상을 코드에서 오타 없이 쓰도록 Dart 코드로 자동 생성해 줍니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | jaspr_cli | Dart로 웹사이트를 만드는 Jaspr 프레임워크의 CLI(개발 서버 실행·빌드) (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | serverpod_cli | Serverpod 백엔드 프레임워크 CLI. pub.dev API로 지금 시점 실제 최신 버전(안정판 latest에 안 잡히는 베타·RC 포함)을 조회해 그 버전으로 설치하므로, 4.x → 5.x처럼 major가 올라가도 손대지 않아도 자동으로 따라갑니다 (jq/curl 조회 실패 시에만 안정판으로 대체 설치, `dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | marionette_mcp | Claude Code의 `marionette` MCP 서버 — 실행 중인 Flutter 앱을 위젯 단위로 조작합니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | mcp_server_dart | Claude Code의 `dart` MCP 서버 — 코드 분석·핫 리로드·패키지 탐색을 Claude가 직접 하게 해줍니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/firebase.svg" width="20" height="20"> | flutterfire_cli | Flutter 프로젝트를 Firebase 프로젝트와 연동해주는 CLI(`flutterfire configure` 등). pub.dev 공개 패키지라 GitHub 인증 없이 설치됩니다 (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | cob (co-bricks) | Mason bricks(코드 스캐폴딩 템플릿) 동기화·관리 CLI. `cc-bricks` 플러그인이 Feature/프로젝트를 빠르게 생성할 때 사용합니다 (`dart pub global activate --source git`로 설치 — 비공개 레포라 GitHub 인증 필요, 보통 위 `gh`에서 1Password로 자동 처리됨) |

**클라우드 / 언어 런타임**

| | 도구 | 용도 |
|---|---|---|
| <img src="assets/icons/gcloud.svg" width="20" height="20"> | gcloud (Google Cloud CLI) | Google Cloud를 터미널에서 다루는 도구. `gcloud-cli` 설치 실패 시 `google-cloud-sdk`로 대체 시도 |
| <img src="assets/icons/python.svg" width="20" height="20"> | Python 최신 3.x | pyenv로 설치되는 최신 안정 버전, `pyenv global`로 기본 지정 |
| <img src="assets/icons/nodejs.svg" width="20" height="20"> | Node.js LTS + npm | nvm으로 설치, `nvm alias default`로 기본 지정 |

**터미널 환경**

| | 도구 | 용도 |
|---|---|---|
| | oh-my-zsh | zsh 설정을 편하게 관리해주는 프레임워크 |
| | powerlevel10k | 터미널 테마 (예쁘고 정보가 많은 프롬프트) |
| <img src="assets/icons/zsh.svg" width="20" height="20"> | zsh-autosuggestions | 이전에 입력한 명령어를 자동으로 제안해주는 플러그인 |
| <img src="assets/icons/zsh.svg" width="20" height="20"> | zsh-syntax-highlighting | oh-my-zsh 커스텀 플러그인으로도 추가 설치 |
| | MesloLGS NF (font-meslo-lg-nerd-font) | powerlevel10k가 아이콘을 제대로 표시하는 데 필요한 폰트 |

</details>

<br>

<a id="after-install"></a>

## ✅ 설치 후 확인할 것

스크립트 맨 마지막에 아래 항목들의 버전을 자동으로 출력해서, 잘 설치됐는지 바로 확인할 수 있게 해줍니다.

```
brew    : ...
Xcode.app: ...
xcode-select: ...
ZenHub 확장(Chrome/Dia): ...
Stats.app: ...
fvm     : ...
flutter : ...
go      : ...
python  : ...
node    : ...
npm     : ...
claude  : ...
codex   : ...
agy(antigravity): ...
slack   : ...
lefthook: ...
상태줄(statusline): ...
git email: ...
GitHub 인증(gh): ...
mcp:figma: ...
op(1Password CLI): ...
mcp:zenhub: ...
mcp:mcp-atlassian(jira): ...
SLANG_GPT_API_KEY: ...
DCM_EMAIL/DCM_CI_KEY: ...
mcp:slack: ...
dart 기본 패키지: ...
marionette: ...
mcp_server_dart: ...
flutterfire_cli: ...
cob(co-bricks): ...
cocode-skills: ...
android : ...
ndk     : ...
avd     : ...
Orca 전체 디스크 접근: ...
```

> `claude`는 공식 설치 스크립트로 `~/.local/bin`에 설치되며, 스크립트가 같은 실행 세션과 `~/.zshrc` 양쪽에 PATH를 반영해 주므로 버전이 바로 표시됩니다. `❌`로 나오면 안내된 수동 설치 명령을 실행해 주세요.

> `Stats.app`은 메뉴막대에 시스템 사용량을 띄워 주는 앱이라, **설치됨과 메뉴막대에 보임이 다릅니다**. 여기 `✓ 설치됨`이 찍혀도 메뉴막대에 아무것도 없다면 아직 한 번도 실행하지 않은 것이니 `open -a Stats`로 최초 1회 실행해 주세요.

> `lefthook`은 커밋·푸시 직전에 검사를 자동으로 돌려주는 Git 훅 관리자입니다. 여기 버전이 찍히면 도구는 준비된 것이고, **실제로 켜는 건 레포마다 한 번씩**입니다 — `lefthook.yml`이 있는 프로젝트 폴더에서 `lefthook install`을 실행하세요(설정 파일이 없는 레포에서는 할 일 없음).

> `GitHub 인증(gh)`이 `❌`이면 바로 아래 `cob(co-bricks)`·`cocode-skills` 둘 다 설치되지 않습니다 — 둘 다 coco-de의 비공개 레포라 GitHub 로그인이 필요하기 때문입니다. 보통은 팀 공용 1Password 항목("API Token" 볼트 > "GitHub API Token" > credential 필드)으로 자동 로그인되며, 항목이 없거나 실패했다면 `gh auth login`을 직접 실행한 뒤 스크립트를 다시 실행하세요.
>
> `op(1Password CLI)`는 **설치 여부와 설정 여부를 따로** 보여줍니다. `⚠ 설치됨 (설정 미완료 — 토큰을 읽지 못했습니다)`라면 CLI는 깔렸지만 금고에서 토큰을 읽지 못한 상태입니다. 원인은 두 가지이고, 스크립트가 화면에 확인 순서(① 앱 CLI 통합 체크 → ② 금고 접근 권한)를 함께 출력해 줍니다 — 아래 **ZenHub·Jira·Slang GPT·DCM·Slack 토큰 · 1Password CLI 설정**을 참고해 주세요.

> `mcp:zenhub`·`mcp:mcp-atlassian`·`mcp:slack`이 `✓ 등록됨`인데 뒤에 `(⚠ 토큰 미주입)`이 붙어 있다면, MCP 서버는 등록됐지만 인증 토큰이 없는 상태입니다. 아래 **ZenHub·Jira·Slang GPT·DCM·Slack 토큰** 안내대로 1Password(앱 CLI 통합 + 팀 'API Token' 볼트 권한)를 준비한 뒤 스크립트를 다시 실행해 주세요.

> `SLANG_GPT_API_KEY`는 Flutter 다국어 문구를 자동 번역해 주는 도구 `slang_gpt`가 쓰는 키입니다. MCP가 아니라 명령줄 도구가 환경변수로 바로 읽는 값이라 등록 여부 없이 **주입됐는지만** 표시합니다. `❌ 미주입`이면 다른 토큰과 같은 원인(앱 CLI 통합 · 'API Token' 볼트 권한)이니 아래 안내를 따라 주세요.

> `DCM_EMAIL/DCM_CI_KEY`는 Dart 코드 품질 검사 도구 `DCM`을 CI/자동화 모드로 인증하는 이메일+키 한 쌍입니다. 이 역시 MCP가 아니라 `dcm` 명령줄 도구가 환경변수로 직접 읽는 값이라 **주입됐는지만** 표시하며, **두 값이 모두 있어야** `✓ 주입됨`으로 나옵니다. `❌ 미주입`이면 다른 토큰과 같은 원인(앱 CLI 통합 · 'API Token' 볼트 권한)이니 아래 안내를 따라 주세요.

> `mcp:slack`은 `slack` MCP(`@modelcontextprotocol/server-slack`)의 등록·인증 상태입니다. zenhub·jira와 같은 기준으로, `SLACK_TEAM_ID`·`SLACK_BOT_TOKEN` **두 값이 모두 있어야** `+ 토큰 주입됨`으로 표시됩니다. `(⚠ 토큰 미주입)`이면 아래 안내를 따라 주세요.

> `Orca 전체 디스크 접근`은 Orca가 다른 앱의 폴더를 읽을 수 있는지(= 허용 창이 반복해서 뜨지 않는지)를 보여줍니다. `⚠ 확인 불가`로 나와도 **문제가 생긴 게 아닙니다** — 이 상태를 조회하려면 조회하는 쪽(터미널)에도 같은 권한이 있어야 해서, 새로 세팅한 맥에서는 대개 확인만 못 하는 것입니다. 이때는 시스템 설정에서 Orca 토글이 켜져 있는지 눈으로 확인해 주세요. 자세한 내용은 아래 [🔐 Orca 전체 디스크 접근 권한](#orca-full-disk-access)에 있습니다.

그 다음, 화면에 안내되는 대로 아래 순서를 진행해주세요.

1. 새 터미널을 열거나 `source ~/.zshrc` 실행
2. **Orca를 완전히 종료(⌘Q, 메뉴막대 아이콘까지)했다가 다시 실행** — 9단계에서 켠 **전체 디스크 접근 권한**은 앱이 시작하는 시점에 읽히기 때문에, 재시작 전에는 적용되지 않습니다. 권한을 아직 안 켰거나 폴더 허용 창이 계속 뜬다면 `./mac-setup.sh --perms-only`로 안내를 다시 받을 수 있습니다 (아래 [🔐 Orca 전체 디스크 접근 권한](#orca-full-disk-access) 참고)
3. **macOS 기본 Terminal.app을 쓰고 있었다면** 폰트가 이미 **MesloLGS NF**로 자동 적용되어 있습니다(7.5단계) — 별도로 할 일 없습니다. **iTerm2 등 다른 터미널 앱**을 쓰고 있었다면 그 앱의 환경설정에서 폰트를 **MesloLGS NF**로 직접 변경해주세요 — 폰트 자체는 자동 설치되지만, 실제로 사용하도록 선택하는 건 직접 해주셔야 powerlevel10k 아이콘이 깨지지 않습니다
4. `p10k configure` 실행 — 아직 p10k 테마 설정을 해본 적이 없다면
5. Android Studio 실행 후 `flutter doctor`로 최종 확인 — SDK/NDK/에뮬레이터/AVD는 스크립트가 이미 자동으로 설치·구성해 두었으므로 첫 실행 설치 마법사를 따로 진행할 필요는 없습니다
6. **(선택) `colima start` 미리 실행 — Jira(Atlassian) MCP를 쓰려면 필요합니다** (아래 🐳 안내 참고). Jira MCP는 docker 컨테이너로 뜨는데, colima가 그 docker 데몬입니다. 이제 `claude`/`cld` 실행 시 꺼져 있으면 자동으로 켜주지만, 최초 기동엔 수십 초가 걸릴 수 있어 미리 켜두면 더 빠릅니다
7. `claude` 실행 후 Claude Code 로그인 (함께 설치된 `codex`는 ChatGPT 계정, `agy`(Antigravity)는 Google 계정으로 각각 처음 실행할 때 한 번 로그인). Claude Code 하단 상태줄(모델·비용·컨텍스트·git 상태)은 6.5단계에서 이미 자동으로 설정됐을 겁니다 — `ccstatusline`이 대화형이라 등록에 실패하면 `awesome-statusline`(size: small)이 자동으로 대신 등록됩니다. 직접 위젯을 골라 커스터마이징하고 싶다면 `npx -y ccstatusline@latest`를, 다른 크기로 바꾸고 싶다면 `curl -fsSL https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.sh | bash -s -- <크기>`를 실행하면 됩니다(크기: xs/s/m/l/xl). 되돌리려면 `~/.claude/settings.json`의 `statusLine` 키만 지우면 됩니다
8. **Claude Code에서 `/mcp` 실행 → figma를 팀 계정으로 OAuth 로그인 (최초 1회)** — 이걸 하지 않으면 figma MCP가 동작하지 않습니다. zenhub·jira·slack MCP는 아래 팀 공용 토큰으로 인증되므로 별도 로그인이 필요 없습니다
9. **설치 검증에 `GitHub 인증(gh): ❌`가 찍혔다면** — `cob(co-bricks)`·`cocode-skills` 둘 다 설치되지 않습니다. 팀 공용 1Password 항목("API Token" 볼트 > "GitHub API Token")으로 자동 로그인을 시도하니, 항목이 없다면 팀 관리자에게 생성을 요청하세요. 그래도 안 되면 `gh auth login`으로 직접 로그인한 뒤 스크립트를 다시 실행하면 됩니다 (`cob(co-bricks)`만 다시 깔면 되는 상황이라면 `./mac-setup.sh --dart-only`가 더 빠릅니다 — `cocode-skills`는 전체 재실행이 필요합니다)
10. Slack CLI로 직접 앱/워크플로를 개발하려면 `slack login`으로 워크스페이스 인증(최초 1회) — Claude Code의 `slack` MCP는 이 로그인과 무관하게 아래 팀 공용 토큰으로 별도 인증됩니다
11. **Git 훅(lefthook)은 레포마다 한 번씩 켜기** — `lefthook.yml`이 있는 프로젝트 폴더에서 `lefthook install`을 실행하면, 그 레포에서 커밋·푸시할 때 포맷/린트/테스트가 자동으로 돌아갑니다 (설정 파일이 없는 레포에서는 할 일 없음)
12. **Stats(시스템 모니터)를 최초 1회 실행** — `open -a Stats`. 설치만으로는 메뉴막대에 나타나지 않고, 한 번 실행해야 CPU·메모리·디스크·네트워크 사용량이 메뉴막대에 표시됩니다. 실행 후 Stats 설정에서 **"로그인 시 시작"** 을 켜 두면 다음부터는 자동으로 떠 있습니다

> ✉️ **Git 이메일 (실행 중 입력)**: 스크립트 실행 도중 Git 설정 단계(3.2)에서 커밋에 사용할 회사 이메일을 물어봅니다. 입력하면 `git config --global user.email`에 저장되고, 이미 설정된 맥이라면 묻지 않고 건너뜁니다. `s` + Enter로 건너뛸 수도 있으며, 그 경우 나중에 터미널에서 `git config --global user.email <이메일>`을 직접 실행하면 됩니다.

<a id="orca-full-disk-access"></a>

> ## 🔐 Orca 전체 디스크 접근 권한 (설치 후 한 번만)
>
> **증상** — Orca를 쓰다 보면 *"Orca이(가) 다른 앱의 데이터에 접근하려고 합니다"* 같은 macOS 허용 창이 계속 뜹니다. 허용을 눌러도 잠시 뒤 또 뜹니다.
>
> **왜 그런가요?** 이 창은 macOS의 개인정보 보호 기능(TCC)이 띄우는 것인데, **"항상 허용" 체크박스가 없습니다.** 허용을 눌러도 **그 순간 접근한 폴더 하나만** 기록되기 때문에, Orca가 다른 앱의 폴더를 새로 읽을 때마다 같은 창이 다시 뜹니다. Orca는 코딩 에이전트라 작업 폴더와 여러 도구의 설정 폴더를 폭넓게 읽어서, 이 반복이 유난히 자주 일어납니다.
>
> **근본 해결 — 전체 디스크 접근 권한을 한 번 켜기.** 한 번에 모든 앱 데이터 접근을 허용하는 유일한 방법입니다. 스크립트 9단계가 이 창을 자동으로 열고 안내해 주며, 나중에 다시 하고 싶으면 `./mac-setup.sh --perms-only`로 그 단계만 다시 실행할 수 있습니다.
>
> 1. **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한**
> 2. 목록에 **Orca가 있으면 토글을 켜고**, 없으면 왼쪽 아래 **`+`** 로 `/Applications/Orca.app`을 추가합니다 (스크립트가 함께 열어 준 Finder 창에서 드래그해도 됩니다)
> 3. **Orca를 완전히 종료(⌘Q — 메뉴막대 아이콘까지)한 뒤 다시 실행합니다.** 권한은 앱이 **시작하는 시점**에 읽히므로 재시작 전에는 적용되지 않습니다. 시스템 설정이 **"종료 후 다시 열기"** 버튼을 띄우면 그 버튼을 눌러도 됩니다
>
> 설정 창을 직접 바로 열고 싶다면:
>
> ```bash
> open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
> ```
>
> **이미 눌렀던 허용/거부 기록 확인** — **개인정보 보호 및 보안 → 파일 및 폴더**에서 Orca 항목을 펼치면 지금까지 허용·거부한 폴더 목록이 보입니다. 실수로 **"허용 안 함"** 을 누른 항목이 있으면 여기서 켜 주면 됩니다.
>
> **권한이 꼬여서 창이 계속 뜰 때** — 거부 기록이 캐시되어 이상 동작하는 경우입니다. 초기화한 뒤 위 순서대로 다시 켜 주세요.
>
> ```bash
> tccutil reset SystemPolicyAllFiles com.stablyai.orca   # 전체 디스크 접근 기록만 초기화
> tccutil reset All com.stablyai.orca                    # 전부 초기화 (마이크·화면 기록 등도 다시 물어봄)
> ```
>
> 스크립트는 이 명령을 **대신 실행하지 않습니다** — 정상적으로 허용해 둔 기록까지 지워질 수 있어, 직접 판단해서 실행하시는 편이 안전합니다.
>
> **왜 스크립트가 권한까지 자동으로 켜주지 않나요?** 권한 기록은 macOS가 SIP(시스템 무결성 보호)로 잠가 두어서, 관리자 권한으로도 프로그램이 직접 켤 수 없습니다. 사람이 시스템 설정에서 직접 켜는 것이 유일한 방법이라, 스크립트는 **상태 확인 · 설정 창 자동 열기 · 안내**까지만 대신해 줍니다. (회사가 관리하는 기기라면 MDM의 PPPC 프로파일로 미리 배포할 수도 있지만, 개인 맥에서는 위 방법이 표준입니다.)
>
> ⚠️ **이 권한의 범위는 알고 계시는 게 좋습니다.** 전체 디스크 접근 권한은 말 그대로 **홈 폴더 전체와 다른 앱의 데이터까지 읽을 수 있는 강한 권한**입니다. Orca는 워크스페이스와 도구 설정을 폭넓게 읽어야 하는 코딩 에이전트라 성격상 맞는 권한이지만, 무엇을 허용하는지 이해한 뒤 켜 주세요. 부담스럽다면 켜지 않고 폴더별 허용 창을 그때그때 눌러도 동작은 합니다 (창이 자주 뜰 뿐입니다).

> ## 🐳 Jira는 docker(colima) 데몬이 필요합니다 — 이제 자동으로 켜집니다
>
> **Jira MCP는 docker 컨테이너로 뜨고, colima가 그 docker 데몬입니다.** 예전엔 `claude` 실행 전에 `colima start`를 매번 손으로 켜야 했지만, 이제 `~/.zshrc`의 `claude`/`cld` 함수가 실행 직전에 docker 데몬 상태를 확인해 **꺼져 있으면 자동으로 `colima start`를 실행**합니다.
>
> ⚠️ 이 자동 기동은 **팀 `.zshrc`를 쓸 때만** 동작합니다. [예전 맥의 `.zshrc`를 가져오신 경우](#quickstart)에는 그 함수가 없으므로 `colima start`를 직접 실행하셔야 합니다.
>
> ```bash
> claude    # 또는 cld — colima(docker)가 꺼져 있으면 자동으로 켠 뒤 이어서 실행됩니다
> ```
>
> - **왜 docker가 필요한가?** Jira MCP는 파이썬 서버라서, 팀 전원이 똑같이 동작하도록 **docker 컨테이너**로 실행됩니다. colima가 그 docker 엔진입니다.
> - **자동 기동이 안 보이면**: 최초 콜드 스타트는 수십 초가 걸릴 수 있습니다 — `🐳 colima(docker) 데몬이 꺼져 있어 ...` 메시지가 뜨면 정상 동작 중이니 기다려 주세요. 미리 켜두고 싶다면 터미널에서 `colima start`를 직접 실행해도 됩니다.
> - **그래도 안 될 때**: `claude` 안에서 `/mcp`를 보면 `mcp-atlassian`이 연결 실패로 뜨거나 Jira를 물어보면 "연결할 수 없다"는 답이 옵니다 → `colima start`를 직접 실행한 뒤(`docker info`가 에러 없이 나오면 데몬이 켜진 것, `colima status`로도 확인 가능) **새 터미널**에서 `claude`를 다시 켜세요. (자동 기동 함수는 `.zshrc`를 반영한 새 터미널에서만 동작합니다 — `mac-setup.sh`를 처음 돌렸거나 갱신했다면 `source ~/.zshrc` 또는 새 터미널이 필요합니다.)
> - 참고: ZenHub·figma·slack 등 다른 MCP는 docker가 필요 없습니다. **Jira MCP만** docker로 뜹니다.

> 🔑 **ZenHub·Jira·Slang GPT·DCM·Slack·GitHub 토큰 · 1Password CLI 설정 (실행 중 안내됨)**
>
> **이게 무슨 단계인가요?** ZenHub(이슈 보드)·Jira·Slack을 Claude Code에서 쓰거나, 다국어 문구를 자동 번역하는 `slang_gpt`, 코드 품질 검사 도구 `DCM`을 CI 모드로 인증하려면 비밀번호 같은 **토큰/키** 값이 필요합니다. 이 값은 사람마다 복사해 붙여넣지 않도록 **팀 공용 1Password 금고**에 넣어 두었고, **1Password CLI(`op`)** 가 그 금고를 대신 열어 읽어옵니다. `op`는 1Password의 터미널 버전이라고 보시면 되고, 아래 설정은 `op`에게 **"1Password 앱에 이미 로그인해 둔 상태를 그대로 써도 된다"** 고 허락해 주는 과정입니다. (Jira는 예전엔 `/mcp` OAuth 로그인을 매번 해야 했지만, ZenHub처럼 팀 공용 토큰 방식으로 통일했습니다.)
>
> 스크립트 실행 도중 토큰 주입 단계(ZenHub 8.5 · Jira 8.6 · Slang GPT 8.7 · DCM 8.8 · Slack 8.9)에서 1Password 준비가 안 돼 있으면 **화면이 잠깐 멈추고 같은 내용의 안내**가 뜹니다. 아래를 마친 뒤 **Enter**를 누르면 팀 공용 토큰이 자동으로 `~/.zshrc`에 주입됩니다 (지금 하기 어려우면 `s` + Enter로 건너뛰고, 나중에 `./mac-setup.sh --env-only`로 토큰만 다시 주입하면 됩니다 — 전체 설치를 다시 돌릴 필요가 없습니다). 멈춰서 물어보는 건 ZenHub(8.5) 한 곳뿐이고, **op 설정을 한 번만 마치면 ZenHub·Jira·Slang GPT·DCM·Slack 토큰이 함께 주입됩니다.**
>
> **설정 방법 — 1Password 앱에서**
>
> 1. **1Password 앱**을 열고 팀 계정(`team-cocodeinc.1password.com`)으로 로그인
> 2. 앱 → **설정(⌘,) → "개발자" 탭 → "1Password CLI와 통합"** 체크
>    - **"개발자" 탭이 안 보이면**: **설정 → 보안 → "Touch ID로 잠금 해제"** 를 먼저 켜세요
>    - 앱 통합을 켜면 CLI 계정이 자동 등록되므로 `op account add`를 직접 하실 필요는 없습니다
>
> **잘 됐는지 확인하려면** — 새 터미널 창에서:
>
> ```bash
> op account list   # 팀 계정(team-cocodeinc.1password.com)이 목록에 보이면 성공
> ```
>
> 목록이 비어 있거나 계정을 추가할지 되물으면 위 2번 체크가 아직 안 된 것입니다 (되묻는 질문에는 `n`으로 답하세요). 몇 초~수십 초 멈춘다면 1Password 앱이 잠금 해제(Touch ID)를 기다리는 중이니, 1Password 창에서 승인해 주세요.
>
> **잘 안 될 때**
>
> | 증상 | 원인과 해결 |
> |---|---|
> | `op account list`가 비어 있거나 "계정을 추가할까요?"라고 물음 | 앱의 "1Password CLI와 통합"이 꺼져 있습니다 → 질문에는 `n`으로 답하고, 위 2번을 켠 뒤 다시 시도 |
> | 계정은 보이는데 토큰 주입이 계속 실패 | 팀 **"API Token" 금고** 접근 권한이 없는 경우입니다 → 팀 관리자에게 금고 공유를 요청해 주세요 |
> | `op: command not found` | CLI가 설치되지 않았습니다 → `brew install --cask 1password-cli` 후 `./mac-setup.sh --env-only` 실행 |
> | 설치 검증에 `op(1Password CLI): ⚠ 설치됨 (설정 미완료 …)` | 토큰을 읽지 못한 상태입니다 → ① 위 2번(앱 CLI 통합)이 켜져 있는지 확인 후 `./mac-setup.sh --env-only` 실행, ② 이미 켜져 있다면 "API Token" 금고 권한 문제이니 관리자에게 공유 요청 |
> | `op account list`가 한참(수십 초) 멈춰 있음 | 1Password 앱이 승인(Touch ID)을 기다리는 중입니다 → 1Password 창에서 잠금 해제하면 바로 진행됩니다 |
> | `mcp:mcp-atlassian(jira): ✓ 등록됨 (⚠ 토큰 미주입 …)` | op는 되지만 팀 'API Token' 볼트의 'Laputa Atlassian API Token > Jira API Token'을 못 읽는 경우입니다 → 볼트 접근 권한을 팀 관리자에게 요청 후 `./mac-setup.sh --env-only` 실행 |
> | jira MCP가 연결 안 됨 (docker 관련) | jira MCP는 Docker로 뜹니다 → `claude`/`cld` 실행 시 `~/.zshrc`가 자동으로 `colima start`를 시도합니다(최초 콜드 스타트는 수십 초 소요). 그래도 안 되면 **`colima start`를 직접 실행**한 뒤 새 터미널에서 `claude` |
> | 설치 검증에 `SLANG_GPT_API_KEY: ❌ 미주입` | op는 되지만 팀 'API Token' 볼트의 'Slang GPT API Token > credential'을 못 읽는 경우입니다 → 볼트 접근 권한을 팀 관리자에게 요청 후 `./mac-setup.sh --env-only` 실행 |
> | 설치 검증에 `DCM_EMAIL/DCM_CI_KEY: ❌ 미주입` | op는 되지만 팀 'API Token' 볼트의 'DCM CI CD' 항목(사용자명·자격 증명 필드)을 못 읽는 경우입니다 → 볼트 접근 권한을 팀 관리자에게 요청 후 `./mac-setup.sh --env-only` 실행 (이메일·키 중 하나만 읽혀도 미주입으로 표시됩니다) |
> | `mcp:slack: ✓ 등록됨 (⚠ 토큰 미주입 …)` | op는 되지만 팀 'API Token' 볼트의 'Cocode Slack' 항목(SLACK_TEAM_ID·SLACK_BOT_TOKEN 필드)을 못 읽는 경우입니다 → 볼트 접근 권한을 팀 관리자에게 요청 후 `./mac-setup.sh --env-only` 실행 (두 필드 중 하나만 읽혀도 미주입으로 표시됩니다) |
> | 설치 검증에 `GitHub 인증(gh): ❌`이거나 `cob(co-bricks)`/`cocode-skills`가 `❌` | op는 되지만 팀 'API Token' 볼트의 'GitHub API Token > credential'을 못 읽거나 항목이 없는 경우입니다 → 항목이 없다면 팀 관리자에게 생성(레포 read 권한 PAT)을 요청하고, 있다면 볼트 접근 권한을 요청한 뒤 스크립트를 다시 실행하세요. 이 단계는 `--env-only`에는 포함되지 않으므로 전체 스크립트(`./mac-setup.sh`)를 다시 실행해야 합니다 (또는 직접 `gh auth login`). 인증만 고친 뒤 `cob(co-bricks)`만 다시 깔면 될 때는 `./mac-setup.sh --dart-only`가 더 빠릅니다 |
>
> **Jira는 어떻게 인증하나요 (Rovo 안 거침)**
>
> Jira는 **개발팀 공용 계정(`dev@cocode.im`)의 Jira API 토큰**으로 인증합니다. jira MCP는 오픈소스 **`sooperset/mcp-atlassian`(Docker)** 이며, Atlassian 공식 원격 MCP(Rovo)를 거치지 않고 **Jira Cloud REST API에 토큰으로 직접** 붙습니다 — 그래서 조직 Rovo 엔타이틀먼트가 필요 없습니다. 토큰은 팀 공용 1Password **"API Token" 볼트 > "Laputa Atlassian API Token" 항목 > "Jira API Token" 필드**에 있고, op 설정만 되면 raw 토큰이 `JIRA_API_TOKEN`으로 자동 주입됩니다(서버가 이메일+토큰으로 Basic 인증을 내부 처리).
>
> 그래서 팀원은 위 **1Password CLI 설정(op)만 마치고**, **colima/docker를 켜 둔 상태**에서 새 터미널의 `claude`를 쓰면 됩니다. (op는 되는데 "미주입"이면 대개 볼트 접근 권한 문제 → 관리자에게 공유 요청.)
>
> 토큰 값은 1Password에만 저장되고 저장소(git)에는 절대 들어가지 않습니다(claude 설정에도 `${JIRA_API_TOKEN}` 리터럴만 저장).
>
> **Slang GPT 키는 무엇에 쓰나요**
>
> `SLANG_GPT_API_KEY`는 Flutter 앱의 다국어(한국어·영어…) 문구를 자동으로 번역해 주는 도구 **`slang_gpt`** 가 GPT 서비스를 부를 때 쓰는 키입니다. ZenHub·Jira와 달리 **MCP 서버가 아니라 명령줄 도구가 환경변수로 직접 읽는 값**이라, 등록 과정이나 로그인 없이 `~/.zshrc`에 주입되기만 하면 바로 쓸 수 있습니다. 키는 팀 공용 1Password **"API Token" 볼트 > "Slang GPT API Token" 항목 > "credential" 필드**에 있고, op 설정만 되어 있으면 8.7단계에서 자동으로 주입됩니다 (이 단계는 화면을 멈추지 않고, 실패하면 경고만 남기고 넘어갑니다).
>
> **DCM CI 인증 키(DCM_EMAIL·DCM_CI_KEY)는 무엇에 쓰나요**
>
> `DCM_EMAIL`·`DCM_CI_KEY`는 Dart 코드 품질 검사 도구 **`DCM`(Dart Code Metrics)** 을 CI/자동화 모드로 인증할 때 쓰는 **이메일 + 키** 한 쌍입니다. Slang GPT와 마찬가지로 MCP가 아니라 `dcm` 명령줄 도구가 환경변수로 직접 읽는 값이라 등록·로그인 과정이 없습니다. 두 값은 팀 공용 1Password **"API Token" 볼트 > "DCM CI CD" 항목**의 **사용자명(username)=이메일 · 자격 증명(credential)=키** 필드에 있고, op 설정만 되어 있으면 8.8단계에서 자동으로 주입됩니다 (화면을 멈추지 않고, 실패하면 경고만 남기고 넘어갑니다). **두 값이 모두 읽혀야** 주입되며, 하나라도 못 읽으면 반쪽 인증을 막기 위해 아무것도 넣지 않습니다.
>
> **Slack MCP 토큰(SLACK_TEAM_ID·SLACK_BOT_TOKEN)은 무엇에 쓰나요**
>
> `SLACK_TEAM_ID`·`SLACK_BOT_TOKEN`은 Claude Code에 등록되는 **`slack` MCP**(`@modelcontextprotocol/server-slack`, npx로 실행)가 Slack 워크스페이스에 접속할 때 쓰는 **팀 ID + 봇 토큰** 한 쌍입니다. zenhub·jira처럼 MCP 인증용 토큰이라 `claude mcp add slack`에는 `${SLACK_BOT_TOKEN}`·`${SLACK_TEAM_ID}` 리터럴만 등록되고, 실제 값은 `~/.zshrc`에서 런타임에 채워집니다. 두 값은 팀 공용 1Password **"API Token" 볼트 > "Cocode Slack" 항목**의 **SLACK_TEAM_ID · SLACK_BOT_TOKEN** 필드에 있고, op 설정만 되어 있으면 8.9단계에서 자동으로 주입됩니다 (화면을 멈추지 않고, 실패하면 경고만 남기고 넘어갑니다). DCM과 마찬가지로 **두 값이 모두 읽혀야** 주입되며, 하나라도 못 읽으면 반쪽 인증을 막기 위해 아무것도 넣지 않습니다. (Slack CLI로 직접 앱을 개발할 때 쓰는 `slack login`은 이 토큰과 별개입니다.)
>
> ⚠️ **주입 후에는 반드시 새 터미널에서 `claude`를 실행하세요(그리고 docker 데몬이 떠 있어야 합니다).** zenhub·jira·slack MCP는 `claude`를 실행한 시점의 환경변수에서 토큰을 읽습니다. 토큰을 넣기 전에 열어 둔 터미널에서 계속 쓰면 토큰이 전달되지 않습니다. 이때 `/mcp` 화면에는 `Connected`로 보여도 실제 호출은 인증 오류가 납니다.
>
> **GitHub 인증(gh)은 위 토큰들과 뭐가 다른가요**
>
> coco-de 조직의 `co-bricks`·`skills` 레포는 비공개라서, `cob(co-bricks)` 설치(4단계)와 `cocode-skills` 팀 플러그인 설치(3.5단계)에는 GitHub 로그인이 필요합니다. 위 토큰들처럼 `~/.zshrc`에 환경변수로 주입되는 대신, 같은 팀 공용 1Password **"API Token" 볼트 > "GitHub API Token" 항목 > "credential" 필드**(레포 read 권한이면 충분한 Personal Access Token)에서 읽은 값으로 `gh auth login` + `gh auth setup-git`을 대신 실행해 둡니다(3.4단계) — 이후 `git`이 github.com에 접근할 때도 이 인증을 그대로 씁니다. **이미 `gh auth login`이 돼 있다면 건너뜁니다(멱등)**. 위 8.5~8.9 토큰과 달리 이 단계는 준비가 안 돼 있어도 화면을 멈추지 않고 경고만 남긴 뒤 계속 진행하며, `--env-only`로는 재실행되지 않으므로(설치 단계에 속함) 안 됐다면 전체 스크립트를 다시 실행하거나 `gh auth login`을 직접 실행하세요. (`gh auth login`을 마친 뒤 `cob(co-bricks)`만 다시 깔면 되는 상황이라면 `./mac-setup.sh --dart-only`로 그 단계만 다시 돌릴 수 있습니다.)

<br>

<a id="is-it-safe"></a>

## 🔒 안전한가요

네, 안전하게 다시 실행할 수 있도록 설계되어 있습니다.

- **이미 설치된 건 다시 건드리지 않습니다.** 앱/도구별로 설치 여부를 먼저 확인하고, 이미 있으면 `✓ 이미 설치됨`을 출력하고 건너뜁니다. 스크립트를 여러 번 실행해도 문제없습니다. 다만 두 가지는 예외입니다 — **팀 표준에서 빠진 항목**(예전 atlassian OAuth 플러그인, flutter-mcp-toolkit 플러그인)은 재실행 시 **자동으로 정리(제거)** 되고, **zenhub·jira·slack MCP 등록**은 설정이 최신으로 유지되도록 매번 지웠다가 다시 등록합니다. **Dart 글로벌 패키지**(`melos`·`mason_cli` 등)도 매번 최신으로 다시 활성화되는데, 이건 의도된 동작입니다 — 그래서 `./mac-setup.sh --dart-only`가 재설치이자 **업데이트** 역할을 합니다.
- **일부가 실패해도 전체가 멈추지 않습니다.** 개별 항목 설치가 실패하면 `⚠` 표시와 함께 건너뛰고 나머지를 계속 진행합니다.
- **설치 중 y/n 질문에 자동으로 답합니다.** (`NONINTERACTIVE=1`, `CI=true` 설정) 터미널 앞에서 계속 기다리지 않아도 되도록 하기 위함입니다. 사람 입력을 기다리는 곳은 두 종류뿐입니다 — ① **관리자(맥 로그인) 암호**: Homebrew 설치(0) · Xcode 전환(1.5) · 브라우저 확장 등록(1.6), ② **직접 답해야 하는 질문**: **Git 이메일 입력(3.2)** · **ZenHub 토큰 주입(8.5)** · **Orca 권한 안내(9)** 에서만 잠깐 멈춥니다 — 각각 `s`로 건너뛸 수 있고, 이미 설정된 맥이라면 묻지 않습니다. (Jira 토큰 주입(8.6)·Slang GPT 키 주입(8.7)·DCM 키 주입(8.8)·Slack 토큰 주입(8.9)은 ZenHub에서 켠 op 설정을 그대로 재사용하므로 따로 멈추지 않습니다.) (터미널이 아닌 파이프 실행이면 멈추지 않고 건너뜁니다.)
- **Homebrew 자동 설치(0단계)에서 관리자 암호를 한 번 물어볼 수 있습니다.** Homebrew는 이미 있으면 건드리지 않고, 없을 때만 [공식 설치 스크립트](https://brew.sh)를 그대로 실행합니다(비공식 경로를 쓰지 않습니다). **여기만은 실패하면 `⚠` 후 계속이 아니라 스크립트가 멈춥니다** — 이후 단계 대부분이 Homebrew로 설치되기 때문에, 계속 진행하면 전부 실패해서 원인을 알아보기 어려워지기 때문입니다.
- **Xcode 전환(1.5단계)에서 sudo 암호를 한 번 물어볼 수 있습니다.** `xcode-select`가 Command Line Tools를 가리키고 있으면 Xcode.app으로 전환하는데, 이 작업엔 관리자 암호가 필요합니다. 이미 Xcode.app을 가리키고 있다면 묻지 않고 건너뜁니다. (터미널이 아닌 파이프 실행이면 시도하지 않고 건너뜁니다.)
- **Terminal.app 폰트 자동 적용(7.5단계)은 macOS 기본 Terminal.app에서 실행 중일 때만 동작합니다.** 지금 실행 중인 터미널이 Terminal.app이 아니면(예: iTerm2) 건드리지 않고 건너뛰므로, 다른 터미널 앱에서 예상치 못한 창이 뜨는 일은 없습니다.
- **기존 `~/.zshrc`는 자동으로 백업됩니다.** 새 설정을 쓰기 전에 `~/.zshrc.backup.년월일시분초` 형식으로 복사해 둡니다. 마음에 안 들면 이 백업 파일로 언제든 되돌릴 수 있습니다.
- **권한은 스크립트가 대신 켜지 않습니다.** Orca의 [전체 디스크 접근 권한(9단계)](#orca-full-disk-access)은 macOS가 SIP로 잠가 두어 프로그램이 켤 수 없고, 스크립트는 **상태 확인 · 설정 창 열기 · 안내**까지만 합니다. 마지막 토글은 반드시 사용자가 직접 누르며, 켜지 않아도(=`s`로 건너뛰어도) 나머지 설치는 그대로 진행됩니다. 다만 이 권한은 홈 폴더 전체와 다른 앱의 데이터까지 읽을 수 있는 **강한 권한**이니, 무엇을 허용하는지 이해한 뒤 켜 주세요.
- **코드가 전부 공개돼 있습니다.** 이 저장소의 [`mac-setup.sh`](./mac-setup.sh) 파일이 스크립트의 전부이며, 실행 전에 직접 열어서 읽어보실 수 있습니다. [빠른 시작](#quickstart)의 한 줄 실행은 이 저장소의 파일을 그대로 받아 실행하는 것이라 내용이 같지만, **읽어보고 실행하고 싶다면** 같은 섹션의 `git clone` 방식을 쓰시거나 아래처럼 먼저 내려받아 열어보셔도 됩니다.

  ```bash
  mkdir -p ~/co-mac
  curl -fsSL https://raw.githubusercontent.com/coco-de/co-mac/main/mac-setup.sh -o ~/co-mac/mac-setup.sh
  open -e ~/co-mac/mac-setup.sh
  ```

  텍스트 편집기가 열리면 내용을 확인하시고, **다 읽으신 뒤에** 아래를 실행하세요.

  ```bash
  bash ~/co-mac/mac-setup.sh
  ```

<details>
<summary>기존 .zshrc를 가져올 때 자동으로 적용되는 호환성 패치</summary>

<br>

예전 맥의 `.zshrc`를 그대로 가져오는 경우, 새 맥에서도 문제없이 동작하도록 아래 패치가 자동으로 적용됩니다.

- `JAVA_HOME` 경로가 특정 버전으로 하드코딩되어 있으면, openjdk@17이 **설치돼 있을 때만** 잡도록 교체 (아직 안 깔린 맥에서 셸을 열 때마다 에러가 찍히던 문제 방지)
- `~/.local/bin/env`를 무조건 불러오던 줄 → 파일이 있을 때만 실행되도록 가드 추가
- `direnv hook zsh`를 무조건 실행하던 줄 → direnv가 설치돼 있을 때만 실행되도록 가드 추가
- **PATH 중복 제거(`typeset -U path`) 설정을 맨 위에 추가** — 이게 없으면 터미널을 중첩해서 열 때마다(tmux, claude, 서브셸 등) 같은 경로가 계속 쌓입니다. 3단계만 겹쳐도 PATH 항목이 40개 가까이 늘어나 명령 찾는 속도가 느려집니다
- 기존 `.zshrc`가 `~/powerlevel10k` 경로를 직접 참조하는 경우를 위해, 같은 위치에도 powerlevel10k를 추가로 내려받아 둠

**반대로, 자동으로 따라오지 *않는* 것도 있습니다.** 아래는 팀 `.zshrc`에만 들어 있는 설정이라, 예전 `.zshrc`를 가져오시면 직접 추가하셔야 합니다.

- `pyenv init` — 없으면 새 터미널에서 `python`이 "command not found"로 뜹니다 (설치는 돼 있어도 경로가 안 잡힘)
- `ANDROID_HOME` / SDK PATH — 없으면 `adb`·`sdkmanager`·`emulator`를 터미널에서 부를 수 없고, Gradle이 SDK를 못 찾습니다
- `claude`/`cld` 실행 시 colima 자동 기동 함수 — 없으면 Jira MCP를 쓰기 전에 `colima start`를 직접 실행해야 합니다

</details>

<details open>
<summary>⚠️ 보안 주의사항 (반드시 확인해주세요)</summary>

<br>

> **예전 맥의 `.zshrc`에 API 키(Anthropic, Figma, ZenHub, Gemini)가 평문으로 포함되어 있을 수 있습니다.**

이 스크립트는 여러분이 같은 폴더에 넣어둔 `.zshrc`를 그대로 복사해서 사용합니다. 그 파일 안에 개인 API 키가 평문으로 적혀 있다면, 새 맥에도 그대로 옮겨집니다. 아래를 권장합니다.

- 가능하다면 옮기기 전에 **키를 재발급**하세요.
- API 키는 `~/.zshrc` 안에 직접 두지 말고, `~/.zshrc.local` 같은 별도 파일로 분리하는 것을 권장합니다.
- 본인의 `.zshrc`/`.p10k.zsh`를 이 스크립트와 같은 폴더에 넣어두셨다면, **그 폴더를 통째로 압축해서 Slack이나 메일 등으로 외부에 공유하지 마세요.**

</details>

<br>

<a id="troubleshooting"></a>

## 🐛 문제가 생겼나요

<details>
<summary>터미널이 뭔가요? 처음이라 잘 모르겠어요</summary>

<br>

macOS에 기본으로 들어있는 앱입니다. `Cmd + Space`를 눌러 Spotlight 검색을 연 뒤 `터미널` 또는 `Terminal`을 입력하면 찾을 수 있습니다. 마우스로 클릭하는 대신 글자로 명령을 입력해서 컴퓨터에 일을 시키는 화면이라고 생각하시면 됩니다. 이 문서의 회색 박스 안 내용을 그대로 붙여넣고 Enter를 누르면 됩니다.

</details>

<details>
<summary><code>brew: command not found</code> 라고 떠요</summary>

<br>

**스크립트를 실행하기 전이라면 그냥 두셔도 됩니다.** Homebrew가 없으면 스크립트가 0단계에서 자동으로 설치해 주기 때문에, 미리 깔아둘 필요가 없습니다.

**스크립트를 다 돌린 뒤에도 이 메시지가 뜬다면**, 설치는 됐지만 지금 열려 있는 터미널이 아직 경로를 인식하지 못하는 상태입니다. 터미널을 완전히 껐다가 다시 켜거나, `source ~/.zshrc`를 실행해 보세요.

**스크립트 실행 중에 아래 메시지가 뜨면서 멈췄다면**, 자동 설치가 실제로 실패한 경우입니다.

```
❌ Homebrew 자동 설치에 실패했습니다.
```

이후 단계 대부분이 Homebrew를 필요로 해서 일부러 멈추도록 되어 있습니다. 화면에 함께 뜨는 원인 메시지를 확인하시고(대개 관리자 암호를 잘못 입력했거나 네트워크가 끊긴 경우입니다), [brew.sh](https://brew.sh) 안내대로 직접 설치한 뒤 스크립트를 다시 실행해 주세요.

</details>

<details>
<summary>권한 오류(Permission denied)가 떠요</summary>

<br>

스크립트 파일에 실행 권한이 없어서 그렇습니다. 아래 명령어로 실행 권한을 준 뒤 다시 실행해보세요.

```bash
chmod +x mac-setup.sh
./mac-setup.sh
```

</details>

<details>
<summary>중간에 <code>⚠</code> 표시가 뜨고 넘어갔어요. 괜찮은 건가요?</summary>

<br>

네, 괜찮습니다. 해당 항목 하나가 설치에 실패했다는 뜻이며, 스크립트는 멈추지 않고 나머지 항목을 계속 설치합니다. 스크립트를 다시 한번 실행하면 실패했던 항목만 다시 시도됩니다(이미 성공한 항목은 건너뜁니다). 재실행 후에도 계속 실패한다면 [도움이 필요하신가요](#get-help)를 확인해주세요.

</details>

<details>
<summary><code>xcodebuild: error: ... requires Xcode, but active developer directory ... CommandLineTools</code> 라고 떠요</summary>

<br>

`xcode-select`가 전체 Xcode.app이 아니라 Command Line Tools(경량 버전)를 가리키고 있어서 그렇습니다. `mac-setup.sh`를 실행하면 1.5단계에서 자동으로 감지해 Xcode.app으로 전환해 드리니, `Xcode.app`이 `/Applications`에 있는 상태로 스크립트를 (다시) 실행해보세요.

수동으로 직접 고치고 싶다면:

```bash
sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

`/Applications/Xcode.app`이 없다면 App Store에서 Xcode를 먼저 설치해야 합니다.

</details>

<details>
<summary>팀에 새 Dart 패키지가 추가됐다는데 제 맥에는 없어요</summary>

<br>

`mac-setup.sh`가 설치하는 **Dart 글로벌 패키지 목록이 바뀐 경우**입니다. 전체 설치를 다시 돌릴 필요 없이 그 단계만 다시 실행하면 됩니다.

```bash
./mac-setup.sh --dart-only
```

이미 깔려 있던 패키지는 최신으로 다시 활성화되고, 빠진 것만 새로 깔립니다(몇 번을 실행해도 안전합니다). 끝나면 `dart 기본 패키지: ✓ …` 처럼 결과를 요약해 주고, 빠진 게 있으면 그 이름을 알려줍니다.

`❌ dart 명령을 찾지 못했습니다` 가 뜬다면 Flutter/Dart가 아직 준비되지 않은 것입니다. 화면에 뜨는 안내가 두 가지로 갈립니다.

- **fvm도 없는 맥** — 옵션 없이 `./mac-setup.sh`로 전체 설치를 먼저 해주세요.
- **fvm은 있는데 기본 버전이 안 잡힌 맥** — 안내대로 `fvm global stable`을 먼저 실행한 뒤 `./mac-setup.sh --dart-only`를 다시 실행하면 됩니다.

</details>

<details>
<summary>Orca가 다른 앱 폴더에 접근하겠다는 창을 계속 띄워요</summary>

<br>

macOS 개인정보 보호(TCC) 창이라 **"항상 허용"이 없고**, 허용을 눌러도 그때 읽은 폴더 하나만 기록됩니다. 그래서 Orca가 새 폴더를 읽을 때마다 다시 뜹니다. **전체 디스크 접근 권한**을 한 번 켜는 것이 유일한 근본 해결책입니다.

```bash
./mac-setup.sh --perms-only
```

설치는 전부 건너뛰고 권한 상태만 확인해 시스템 설정 창까지 열어 안내해 줍니다. 켠 뒤에는 **Orca를 완전히 종료(⌘Q)했다가 다시 실행**해야 적용됩니다. 자세한 설명과, 권한 기록이 꼬였을 때 초기화하는 방법(`tccutil reset`)은 [🔐 Orca 전체 디스크 접근 권한](#orca-full-disk-access)에 있습니다.

</details>

<details>
<summary>설치 검증에 <code>Orca 전체 디스크 접근: ⚠ 확인 불가</code> 라고 떠요</summary>

<br>

**문제가 생긴 게 아닙니다.** 이 상태를 조회하려면 조회하는 쪽(스크립트를 실행한 터미널)에도 같은 권한이 필요한데, 새로 세팅한 맥의 터미널에는 보통 그 권한이 없습니다. 즉 **권한이 없다는 뜻이 아니라 "확인만 못 했다"** 는 뜻입니다.

**시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한**에서 Orca 토글이 켜져 있는지 눈으로 확인해 주세요. 켜져 있으면 그대로 쓰시면 됩니다.

</details>

<details>
<summary>이미 설치되어 있는데 다시 설치되나요?</summary>

<br>

아니요. 스크립트는 각 항목마다 설치 여부를 먼저 확인하고, 이미 있으면 `✓ 이미 설치됨`을 표시하며 건너뜁니다. 그래서 몇 번을 다시 실행해도 안전합니다.

예외는 **Dart 글로벌 패키지**입니다 — 이쪽은 일부러 매번 최신으로 다시 활성화합니다. 팀 패키지를 최신으로 올리고 싶을 때 `./mac-setup.sh --dart-only`만 돌리면 되는 이유입니다.

</details>

<br>

<a id="get-help"></a>

## 💬 도움이 필요하신가요

혼자 해결하려 애쓰지 않으셔도 됩니다. 스크립트를 실행한 화면(어떤 메시지가 떴는지)을 그대로 캡처해서, 가장 가까운 엔지니어 동료나 온보딩 담당자에게 편하게 물어봐 주세요.
