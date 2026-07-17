# 🍎 co-mac

> 새로 받은 맥북 한 대를 명령어 한 줄로 co:code 팀 전체와 똑같은 개발환경으로 만들어주는 스크립트입니다.

[![Platform](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Script](https://img.shields.io/badge/script-Bash-4EAA25?logo=gnubash&logoColor=white)](./mac-setup.sh)
[![Package Manager](https://img.shields.io/badge/package_manager-Homebrew-FBB040?logo=homebrew&logoColor=white)](https://brew.sh)

이 저장소에는 딱 두 개의 파일만 있습니다.

- [`mac-setup.sh`](./mac-setup.sh) — 개발환경을 자동으로 설치해주는 스크립트
- `README.md` — 지금 보고 계신 이 문서

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

- macOS가 설치된 맥북
- Homebrew 설치 완료 — 없다면 [brew.sh](https://brew.sh) 안내를 따라 먼저 설치해주세요
- Xcode 설치 완료 (App Store에서 설치)

> 💡 **Homebrew가 뭔가요?** macOS에서 개발 도구들을 설치·관리해주는 프로그램입니다. 이 스크립트가 설치하는 대부분의 도구는 Homebrew를 통해 내려받아집니다. `mac-setup.sh`는 Homebrew가 없으면 바로 종료되고 안내 메시지를 보여주니, 먼저 설치해주세요.

### 실행

```bash
git clone https://github.com/coco-de/co-mac.git
cd co-mac
chmod +x mac-setup.sh && ./mac-setup.sh
```

이게 전부입니다. 이후로는 화면에 뜨는 진행 상황(`▶ 단계 이름`)을 지켜보시면 됩니다. 도구별로 이미 설치되어 있으면 `✓`, 새로 설치하면 진행 로그, 일부가 실패해도 `⚠` 표시와 함께 건너뛰고 계속 진행됩니다. 실행 초반에 **커밋에 사용할 회사 이메일**을 한 번 물어보니 입력해주세요 (이미 설정된 맥이라면 묻지 않습니다).

<details>
<summary>예전에 쓰던 맥이 있다면 (선택 사항)</summary>

<br>

예전 맥의 터미널 테마·설정을 그대로 옮겨오고 싶다면, 그 맥에서 `~/.zshrc`, `~/.p10k.zsh` 두 파일을 **이 스크립트와 같은 폴더**에 복사해 둔 뒤 실행하세요. 스크립트가 이 파일들을 감지하면 그대로 복사해서 씁니다.

이 두 파일은 저장소에 들어있지 않습니다. 각자의 개인 설정 파일이라 필요한 분만 직접 준비하시면 됩니다. 파일이 없으면 스크립트가 기본 설정을 새로 만들어 줍니다.

⚠️ 예전 `.zshrc`를 가져오실 경우 [보안 안내](#is-it-safe)를 꼭 확인해주세요.

</details>

<br>

<a id="tech-stack"></a>

## 🧰 우리 팀의 기술 스택

`mac-setup.sh` 하나로 co:code 팀 전체 노트북에 실제로 세팅되는 앱·CLI·언어 런타임을 한눈에 모았습니다. 아이콘은 대부분 [Simple Icons](https://simpleicons.org)에서 받아 이 저장소의 [`assets/icons/`](./assets/icons)에 함께 보관하고 있습니다. Simple Icons에 없는 앱(Slack·Dia·Orca·Lumide)은 실제 설치되는 앱의 아이콘을 그대로 추출해 사용했습니다. 공식 브랜드 아이콘이 아직 없는 도구는 이름만 표기했습니다.

<br>

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

<sub>※ Slack · Dia · Orca · Lumide는 Simple Icons에 없어, 실제 설치되는 앱 아이콘을 그대로 추출해 사용했습니다. awscli, pyenv, colima, direnv, oh-my-zsh, powerlevel10k, MesloLGS NF는 공식 브랜드 아이콘이 없어 텍스트로만 표기했습니다. DCM · serverpod_cli · marionette_mcp는 Dart 생태계 도구라 Dart 아이콘으로 대신 표기했습니다. op(1Password CLI)는 1Password의 커맨드라인 버전이라 1Password 아이콘을 함께 사용했습니다.</sub>

<br>

<a id="whats-installed"></a>

## 📦 무엇이 설치되나요

| 분류 | 항목 |
|---|---|
| 🖥 GUI 앱 | Android Studio, Slack, Figma, Claude Desktop, Google Chrome, Dia, 1Password, Tailscale, Orca, Lumide |
| 🔌 Claude MCP | figma·flutter-mcp-toolkit 플러그인 자동 설치 + maestro CLI, flutter-mcp-toolkit CLI, marionette·dart MCP, zenhub·atlassian(jira) MCP 자동 등록. `ZENHUB_API_TOKEN`·`ATLASSIAN_MCP_TOKEN`(팀 공용 토큰)은 1Password CLI(`op`)로 `~/.zshrc`에 자동 주입 — git에 커밋 안 됨 (⚠️ figma는 최초 1회 `/mcp` OAuth 로그인. zenhub·atlassian은 OAuth 대신 1Password 팀 공용 토큰으로 인증 — 1Password 앱의 CLI 통합 필요, atlassian은 조직 관리자의 서비스 계정 키 발급도 필요 — [설정 방법](#after-install). flutter-mcp-toolkit은 인증 불필요하나, 특정 Flutter 프로젝트에서 쓰려면 해당 프로젝트에서 `flutter-mcp-toolkit codegen-init` 1회 실행 필요) |
| 🧩 cocode-skills 팀 플러그인 | 사설 레포 `coco-de/skills`의 `install.sh`로 cc-* 플러그인 번들(marionette·dart·figma·dev-cycle·coui 등) 자동 동기화 (⚠️ `gh auth login` 인증 필요, 미인증 시 건너뜀) |
| 📱 Android SDK | cmdline-tools, platform-tools, build-tools, platforms, NDK, 에뮬레이터 시스템 이미지, AVD까지 전부 자동 설치·구성 (Android Studio 첫 실행 마법사 불필요) |
| 🛠 CLI 도구 | go, pyenv, nvm, git, gh, cocoapods, fastlane, awscli, colima, docker, docker-compose, zsh-syntax-highlighting, direnv, openjdk@17, Claude Code, op(1Password CLI) |
| ✉️ Git 설정 | 커밋에 사용할 회사 이메일을 실행 중에 입력받아 전역 설정(`git config --global user.email`) — 이미 설정돼 있으면 묻지 않고 건너뜀 |
| 🐦 Flutter | fvm(버전 관리자)으로 Flutter stable 채널 글로벌 설정, DCM(Dart 코드 품질 검사 도구) |
| 🎯 Dart 글로벌 패키지 | serverpod_cli 4.0.0-beta.0, marionette_mcp |
| ☁️ 클라우드 | Google Cloud CLI (gcloud) |
| 🐍 언어 런타임 | Python 최신 3.x (pyenv), Node.js LTS + npm (nvm) |
| 💻 터미널 환경 | oh-my-zsh, powerlevel10k 테마, zsh-autosuggestions, zsh-syntax-highlighting, MesloLGS NF 폰트 |

모든 항목은 이미 설치되어 있으면 건너뛰도록 되어 있어, 스크립트를 여러 번 실행해도 안전합니다.

<details>
<summary>도구별 상세 설명 펼쳐보기 (하나하나 뭔지 궁금하신 분만)</summary>

<br>

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
| <img src="assets/icons/orca.png" width="20" height="20"> | Orca | AI 코딩 에이전트 도구 (stablyai/orca 탭) |
| <img src="assets/icons/lumide.png" width="20" height="20"> | Lumide | 에이전트 네이티브 코드 에디터 IDE ([lumide.dev](https://lumide.dev)) |

이미 `/Applications`에 앱이 설치되어 있으면 건너뜁니다.

**Android SDK (자동 설치·구성)**

Android Studio 앱만 설치하면 SDK는 비어 있어서, 원래는 앱을 한 번 실행해 설치 마법사를 직접 눌러가며 구성 요소를 받아야 합니다. 이 스크립트는 `android-commandlinetools`(Homebrew)로 받은 `sdkmanager`/`avdmanager`를 이용해 아래 항목을 전부 커맨드라인에서 자동으로 설치·구성하므로, 그 과정이 필요 없습니다.

| 도구 | 용도 |
|---|---|
| cmdline-tools | Android SDK를 터미널에서 다루는 도구 모음 (`sdkmanager`, `avdmanager`). Homebrew 버전은 부트스트랩으로만 쓰고, 최신 버전을 표준 위치(`$ANDROID_HOME/cmdline-tools/latest`)에 정식 설치합니다 |
| platform-tools | `adb` 등 기기·에뮬레이터와 통신하는 도구 |
| build-tools | 최신 안정 버전을 자동으로 찾아 설치 |
| platforms | 최신 안정 Android API 플랫폼을 자동으로 찾아 설치 |
| NDK | 네이티브(C/C++) 코드가 포함된 안드로이드 빌드에 필요, 최신 안정 버전 자동 설치 |
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
| <img src="assets/icons/github.svg" width="20" height="20"> | gh | GitHub를 터미널에서 다루는 도구 |
| <img src="assets/icons/cocoapods.svg" width="20" height="20"> | cocoapods | iOS 라이브러리 의존성 관리자 |
| <img src="assets/icons/fastlane.svg" width="20" height="20"> | fastlane | 앱 빌드·배포 자동화 도구 |
| | awscli | AWS(아마존 클라우드)를 터미널에서 다루는 도구 |
| | colima | Docker Desktop 없이 가볍게 컨테이너를 실행하는 도구 |
| <img src="assets/icons/docker.svg" width="20" height="20"> | docker / docker-compose | 컨테이너 실행 및 관리 CLI (colima와 함께 사용) |
| <img src="assets/icons/zsh.svg" width="20" height="20"> | zsh-syntax-highlighting | 터미널 명령어에 색을 입혀 오타를 줄여주는 플러그인 |
| | direnv | 폴더별로 필요한 환경 변수를 자동으로 불러와 주는 도구 |
| <img src="assets/icons/openjdk.svg" width="20" height="20"> | openjdk@17 | 자바 17 (Android 빌드에 필요) |
| <img src="assets/icons/claude.svg" width="20" height="20"> | Claude Code | 터미널에서 대화하듯 코드를 작성·수정하는 Claude CLI (공식 설치 스크립트 `claude.ai/install.sh`로 설치, `~/.local/bin`) |
| <img src="assets/icons/1password.svg" width="20" height="20"> | op (1Password CLI) | 1Password 금고를 **터미널에서** 열어보는 명령. 1Password 앱과 같은 금고를 보며, 앱에 로그인해 둔 상태를 그대로 빌려 씁니다. 이 스크립트는 팀 공용 ZenHub·Atlassian 토큰을 금고에서 읽어 `~/.zshrc`에 자동으로 넣어주는 데 사용합니다 (설정 방법은 아래 [ZenHub·Atlassian 토큰 · 1Password CLI 설정](#after-install) 참고) |

**Flutter / Dart**

| | 도구 | 용도 |
|---|---|---|
| <img src="assets/icons/flutter.svg" width="20" height="20"> | fvm | Flutter 버전 관리자. `fvm global stable`로 stable 채널을 글로벌 설정 |
| <img src="assets/icons/dart.svg" width="20" height="20"> | DCM (Dart Code Metrics) | Dart 코드 품질 검사 도구 |
| <img src="assets/icons/dart.svg" width="20" height="20"> | serverpod_cli 4.0.0-beta.0 | Serverpod 백엔드 프레임워크 CLI (`dart pub global activate`로 설치) |
| <img src="assets/icons/dart.svg" width="20" height="20"> | marionette_mcp | Dart 글로벌 패키지 (`dart pub global activate`로 설치) |

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
fvm     : ...
flutter : ...
go      : ...
python  : ...
node    : ...
npm     : ...
claude  : ...
git email: ...
mcp:figma: ...
op(1Password CLI): ...
mcp:zenhub: ...
mcp:atlassian: ...
maestro : ...
marionette: ...
mcp_server_dart: ...
mcp:flutter-mcp-toolkit: ...
cocode-skills: ...
android : ...
ndk     : ...
avd     : ...
```

> `claude`는 공식 설치 스크립트로 `~/.local/bin`에 설치되며, 스크립트가 같은 실행 세션과 `~/.zshrc` 양쪽에 PATH를 반영해 주므로 버전이 바로 표시됩니다. `❌`로 나오면 안내된 수동 설치 명령을 실행해 주세요.

> `op(1Password CLI)`는 **설치 여부와 설정 여부를 따로** 보여줍니다. `⚠ 설치됨 (설정 미완료 — 토큰을 읽지 못했습니다)`라면 CLI는 깔렸지만 금고에서 토큰을 읽지 못한 상태입니다. 원인은 두 가지이고, 스크립트가 화면에 확인 순서(① 앱 CLI 통합 체크 → ② 금고 접근 권한)를 함께 출력해 줍니다 — 아래 **ZenHub·Atlassian 토큰 · 1Password CLI 설정**을 참고해 주세요.

> `mcp:zenhub`·`mcp:atlassian`이 `✓ 등록됨`인데 뒤에 `(⚠ 토큰 미주입)`이 붙어 있다면, MCP 서버는 등록됐지만 인증 토큰이 없는 상태입니다. 아래 **ZenHub·Atlassian 토큰** 안내대로 1Password를 준비한 뒤 스크립트를 다시 실행해 주세요. (atlassian은 조직 관리자의 서비스 계정 키 발급도 필요 — 아래 참고)

그 다음, 화면에 안내되는 대로 아래 순서를 진행해주세요.

1. 새 터미널을 열거나 `source ~/.zshrc` 실행
2. 터미널 앱(iTerm2/터미널) 환경설정에서 폰트를 **MesloLGS NF**로 변경 — 폰트 자체는 자동 설치되지만, 실제로 사용하도록 선택하는 건 직접 해주셔야 powerlevel10k 아이콘이 깨지지 않습니다
3. `p10k configure` 실행 — 아직 p10k 테마 설정을 해본 적이 없다면
4. Android Studio 실행 후 `flutter doctor`로 최종 확인 — SDK/NDK/에뮬레이터/AVD는 스크립트가 이미 자동으로 설치·구성해 두었으므로 첫 실행 설치 마법사를 따로 진행할 필요는 없습니다
5. `claude` 실행 후 Claude Code 로그인

> ✉️ **Git 이메일 (실행 중 입력)**: 스크립트 실행 도중 Git 설정 단계(3.2)에서 커밋에 사용할 회사 이메일을 물어봅니다. 입력하면 `git config --global user.email`에 저장되고, 이미 설정된 맥이라면 묻지 않고 건너뜁니다. `s` + Enter로 건너뛸 수도 있으며, 그 경우 나중에 터미널에서 `git config --global user.email <이메일>`을 직접 실행하면 됩니다.

> 🔑 **ZenHub·Atlassian 토큰 · 1Password CLI 설정 (실행 중 안내됨)**
>
> **이게 무슨 단계인가요?** ZenHub(이슈 보드)와 Atlassian(Jira)을 Claude Code에서 쓰려면 비밀번호 같은 **토큰** 값이 필요합니다. 이 값은 사람마다 복사해 붙여넣지 않도록 **팀 공용 1Password 금고**에 넣어 두었고, **1Password CLI(`op`)** 가 그 금고를 대신 열어 읽어옵니다. `op`는 1Password의 터미널 버전이라고 보시면 되고, 아래 설정은 `op`에게 **"1Password 앱에 이미 로그인해 둔 상태를 그대로 써도 된다"** 고 허락해 주는 과정입니다. (Atlassian은 예전엔 `/mcp` OAuth 로그인을 매번 해야 했지만, ZenHub처럼 팀 공용 토큰 방식으로 통일했습니다.)
>
> 스크립트 실행 도중 토큰 주입 단계(ZenHub 8.5 · Atlassian 8.6)에서 1Password 준비가 안 돼 있으면 **화면이 잠깐 멈추고 같은 내용의 안내**가 뜹니다. 아래를 마친 뒤 **Enter**를 누르면 팀 공용 토큰이 자동으로 `~/.zshrc`에 주입됩니다 (지금 하기 어려우면 `s` + Enter로 건너뛰고, 나중에 스크립트를 재실행하면 주입됩니다). op 설정은 한 번만 하면 ZenHub·Atlassian 토큰이 함께 주입됩니다.
>
> **설정 방법 — 1Password 앱에서**
>
> 1. **1Password 앱**을 열고 팀 계정(`team-cocodeinc.1password.com`)으로 로그인
> 2. 앱 → **설정(⌘,) → "개발자" 탭 → "1Password CLI와 통합"** 체크
>    - **"개발자" 탭이 안 보이면**: **설정 → 보안 → "Touch ID로 잠금 해제"**를 먼저 켜세요
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
> | `op: command not found` | CLI가 설치되지 않았습니다 → `brew install --cask 1password-cli` 후 스크립트 재실행 |
> | 설치 검증에 `op(1Password CLI): ⚠ 설치됨 (설정 미완료 …)` | 토큰을 읽지 못한 상태입니다 → ① 위 2번(앱 CLI 통합)이 켜져 있는지 확인 후 재실행, ② 이미 켜져 있다면 "API Token" 금고 권한 문제이니 관리자에게 공유 요청 |
> | `op account list`가 한참(수십 초) 멈춰 있음 | 1Password 앱이 승인(Touch ID)을 기다리는 중입니다 → 1Password 창에서 잠금 해제하면 바로 진행됩니다 |
> | `mcp:atlassian: ✓ 등록됨 (⚠ 토큰 미주입 …)` | op는 되지만 Atlassian 서비스 계정 키가 아직 1Password에 없는 경우입니다 → 아래 **Atlassian 추가 준비** 참고 |
>
> **Atlassian 추가 준비 (조직 관리자 작업, 1회)**
>
> Atlassian은 ZenHub와 달리 **조직 관리자만 발급할 수 있는 서비스 계정 키**로 인증합니다. 관리자가 아래 2개를 마쳐 팀 공용 1Password에 넣어 두면, 그 뒤로는 팀원 누구나 스크립트만 재실행하면 자동 주입됩니다.
>
> 1. Atlassian 관리자 설정에서 **"API 토큰 인증(machine-to-machine)"** 활성화
> 2. **서비스 계정 API 키** 발급 → 팀 **"API Token" 볼트 > "Atlassian MCP Token" > credential** 필드에 저장
>
> 이게 갖춰지기 전까지는 `mcp:atlassian`이 "등록됨 + 토큰 미주입" 상태로 남습니다(스크립트는 멈추지 않고 계속 진행 — ZenHub가 토큰 생기기 전과 동일).
>
> 토큰 값은 1Password에만 저장되고 저장소(git)에는 절대 들어가지 않습니다.
>
> ⚠️ **주입 후에는 반드시 새 터미널에서 `claude`를 실행하세요.** zenhub·atlassian MCP는 `claude`를 실행한 시점의 환경변수에서 토큰을 읽습니다. 토큰을 넣기 전에 열어 둔 터미널에서 계속 쓰면 토큰이 전달되지 않습니다. 이때 `/mcp` 화면에는 `Connected`로 보이지만 — 이건 **서버 연결만 됐다는 뜻이지 로그인됐다는 뜻이 아닙니다** — 실제로 ZenHub/Jira를 호출하는 순간 `Missing Authorization token` 오류가 납니다.

<br>

<a id="is-it-safe"></a>

## 🔒 안전한가요

네, 안전하게 다시 실행할 수 있도록 설계되어 있습니다.

- **이미 설치된 건 다시 건드리지 않습니다.** 앱/도구별로 설치 여부를 먼저 확인하고, 이미 있으면 `✓ 이미 설치됨`을 출력하고 건너뜁니다. 스크립트를 여러 번 실행해도 문제없습니다.
- **일부가 실패해도 전체가 멈추지 않습니다.** 개별 항목 설치가 실패하면 `⚠` 표시와 함께 건너뛰고 나머지를 계속 진행합니다.
- **설치 중 y/n 질문에 자동으로 답합니다.** (`NONINTERACTIVE=1`, `CI=true` 설정) 터미널 앞에서 계속 기다리지 않아도 되도록 하기 위함입니다. 단 두 곳, **Git 이메일 입력(3.2)** 과 **ZenHub 토큰 주입(8.5)** 에서만 잠깐 멈춰 입력을 기다립니다 — 각각 `s`로 건너뛸 수 있고, 이미 설정된 맥이라면 묻지 않습니다. (Atlassian 토큰 주입(8.6)은 ZenHub에서 켠 op 설정을 그대로 재사용하므로 따로 멈추지 않습니다.) (터미널이 아닌 파이프 실행이면 멈추지 않고 건너뜁니다.)
- **기존 `~/.zshrc`는 자동으로 백업됩니다.** 새 설정을 쓰기 전에 `~/.zshrc.backup.년월일시분초` 형식으로 복사해 둡니다. 마음에 안 들면 이 백업 파일로 언제든 되돌릴 수 있습니다.
- **코드가 전부 공개돼 있습니다.** 이 저장소의 [`mac-setup.sh`](./mac-setup.sh) 파일이 스크립트의 전부이며, 실행 전에 직접 열어서 읽어보실 수 있습니다.

<details>
<summary>기존 .zshrc를 가져올 때 자동으로 적용되는 호환성 패치</summary>

<br>

예전 맥의 `.zshrc`를 그대로 가져오는 경우, 새 맥에서도 문제없이 동작하도록 아래 패치가 자동으로 적용됩니다.

- `JAVA_HOME` 경로가 특정 버전으로 하드코딩되어 있으면, `brew --prefix openjdk@17` 기반 경로로 교체
- `~/.local/bin/env`를 무조건 불러오던 줄 → 파일이 있을 때만 실행되도록 가드 추가
- `direnv hook zsh`를 무조건 실행하던 줄 → direnv가 설치돼 있을 때만 실행되도록 가드 추가
- 기존 `.zshrc`가 `~/powerlevel10k` 경로를 직접 참조하는 경우를 위해, 같은 위치에도 powerlevel10k를 추가로 내려받아 둠

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

Homebrew가 설치되어 있지 않거나, 설치는 됐지만 터미널이 아직 경로를 인식하지 못하는 상태입니다.

1. [brew.sh](https://brew.sh)에서 안내하는 방법으로 Homebrew를 설치하세요.
2. 설치가 끝나면 안내 메시지에 나온 대로 터미널을 완전히 껐다가 다시 켜세요.
3. `mac-setup.sh`를 다시 실행하세요.

스크립트도 Homebrew가 없으면 `❌ Homebrew가 없습니다. 먼저 설치하세요: https://brew.sh` 라는 메시지를 보여주고 스스로 멈추도록 되어 있습니다.

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
<summary>이미 설치되어 있는데 다시 설치되나요?</summary>

<br>

아니요. 스크립트는 각 항목마다 설치 여부를 먼저 확인하고, 이미 있으면 `✓ 이미 설치됨`을 표시하며 건너뜁니다. 그래서 몇 번을 다시 실행해도 안전합니다.

</details>

<br>

<a id="get-help"></a>

## 💬 도움이 필요하신가요

혼자 해결하려 애쓰지 않으셔도 됩니다. 스크립트를 실행한 화면(어떤 메시지가 떴는지)을 그대로 캡처해서, 가장 가까운 엔지니어 동료나 온보딩 담당자에게 편하게 물어봐 주세요.
