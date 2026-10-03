# 💻 desktop

> 새로 받은 컴퓨터 한 대를 명령어 한 줄로 co:code 팀 전체와 똑같은 개발환경으로 만들어주는 스크립트입니다.

[![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)](./macos/)
[![Windows](https://img.shields.io/badge/Windows_10%2F11-0078D4?logo=windows&logoColor=white)](./windows/)
[![Linux](https://img.shields.io/badge/Ubuntu_22.04%2B-E95420?logo=ubuntu&logoColor=white)](./linux/)

co:code는 엔지니어뿐 아니라 디자이너, PM도 하나의 엔지니어링 조직 아래에서 함께 일합니다. **직군과 상관없이, 새로 합류한 모든 팀원이 자기 OS에 맞는 스크립트 하나로 노트북을 세팅**합니다.

쓰는 컴퓨터를 고르면 됩니다. 세 안내는 **같은 도구 목록을 각자의 OS 방식으로** 설치합니다.

**OpenCode·Claude Code에는 기본 MCP 10개가 함께 등록됩니다:** `cob` · `dart` · `figma` · `marionette` · `atlassian` · `mobbin` · `slack` · `zenhub` · `chrome-devtools` · `playwright`. 설치 후 두 도구를 새 터미널에서 다시 실행하고, Figma·Mobbin의 최초 OAuth 로그인을 마쳐 주세요. 자세한 인증·확인 방법은 각 OS 안내에 있습니다.

**브라우저 디버깅(`chrome-devtools`)은 macOS에서 실행 중인 Dia에 연결**합니다. [Dia 리모트 디버깅 허용 순서](./macos/README.md#dia-remote-debugging)를 따라 주세요. Windows·Linux에서는 별도 Chrome을 실행합니다.

<br>

## 🍎 맥북 (macOS)

자세한 안내: **[macos/README.md](./macos/README.md)**

터미널을 열고 아래 한 줄을 붙여넣은 뒤 Enter를 누르세요.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/coco-de/desktop/main/macos/mac-setup.sh)"
```

<br>

## 🪟 윈도우 (Windows 10/11)

자세한 안내: **[windows/README.md](./windows/README.md)**

시작 메뉴에서 `PowerShell`을 열고, 아래 한 줄을 붙여넣은 뒤 Enter를 누르세요.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; $s="$env:TEMP\win-setup.ps1"; iwr -UseBasicParsing https://raw.githubusercontent.com/coco-de/desktop/main/windows/win-setup.ps1 -OutFile $s; Unblock-File $s; & $s
```

<br>

## 🐧 리눅스 (Ubuntu 22.04+ / Debian 12+)

자세한 안내: **[linux/README.md](./linux/README.md)**

터미널을 열고 (**Ctrl + Alt + T**), 아래 한 줄을 붙여넣은 뒤 Enter를 누르세요.

```bash
d="$(mktemp -d)" && curl -fsSL https://raw.githubusercontent.com/coco-de/desktop/main/linux/linux-setup.sh -o "$d/linux-setup.sh" && bash "$d/linux-setup.sh"
```

<br>

## 📁 저장소 구조

| 폴더 | 스크립트 | 대상 |
|------|----------|------|
| [macos/](./macos/) | `mac-setup.sh` | macOS (Homebrew) |
| [windows/](./windows/) | `win-setup.ps1` | Windows 10/11 (winget + Scoop) |
| [linux/](./linux/) | `linux-setup.sh` | Ubuntu 22.04+ / Debian 12+ (apt + snap) |

프로그래밍을 잘 모르셔도 괜찮습니다. 각 폴더의 안내만 따라 하시면 됩니다. 실행 중에는 지금 무엇을 하고 있는지 화면에 계속 안내 문구가 표시됩니다.

> 예전에는 `coco-de/co-mac`, `coco-de/co-win`, `coco-de/co-linux` 세 저장소로 나뉘어 있었습니다. 지금은 이 저장소 하나입니다. 예전에 쓰던 한 줄 명령도 그대로 동작하도록 연결해 두었습니다.

## 🧪 설치 스크립트 변경 검증

MCP 등록 코드는 전체 설치 대신 임시 홈 폴더에서 검증할 수 있습니다. Python 3·bash·jq가 있는 환경에서 아래를 실행하세요. 개인 설정이나 실제 토큰은 사용하지 않습니다.

PR과 `main` 푸시에서도 [MCP 설정 검사](.github/workflows/default-mcp.yml)가 Python 회귀·Bash 문법·Windows PowerShell 검사를 자동 실행합니다.

```bash
python3 -m unittest discover -s tests -v
bash -n macos/mac-setup.sh
bash -n linux/linux-setup.sh
```

Windows 문법·설정 병합은 PowerShell 7에서 `pwsh -NoProfile -File tests/default-mcp.Tests.ps1`로 검증합니다. macOS·Linux에서 같은 검사를 하려면 Docker를 사용하세요.

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/work:ro" mcr.microsoft.com/powershell:latest \
  pwsh -NoProfile -File /work/tests/default-mcp.Tests.ps1 -SetupScript /work/windows/win-setup.ps1
```
