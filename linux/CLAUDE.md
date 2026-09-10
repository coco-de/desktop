# co-linux

새 우분투 PC를 co:code 팀 표준 개발환경으로 세팅하는 스크립트 레포. 핵심 파일은 `linux-setup.sh`(설치 스크립트)와 `README.md`(문서) 둘뿐이며, 두 파일은 항상 같은 내용을 가리켜야 한다.

**형제 레포 — 팀 표준 도구가 바뀌면 셋을 함께 갱신해야 한다:**

| 레포 | 스크립트 | 방식 |
|------|----------|------|
| [coco-de/co-mac](https://github.com/coco-de/co-mac) | `mac-setup.sh` | Homebrew |
| [coco-de/co-win](https://github.com/coco-de/co-win) | `win-setup.ps1` | winget + Scoop |
| **co-linux** (여기) | `linux-setup.sh` | apt + snap |

## 필수 규칙

- **`linux-setup.sh`에서 도구를 추가/삭제/변경할 때는 반드시 `sync-tool-docs` 스킬을 사용해** README.md와 스크립트 내 log/주석/검증 문구를 함께 갱신한다. 코드만 고치고 문서를 남겨두면 안 된다.
- **형제 레포와의 대응 관계를 항상 확인한다.** 도구를 추가하면 맥·윈도우에도 있는지, 빠뜨렸다면 왜인지를 README의 `🍎 맥과 무엇이 다른가요` 섹션에 남긴다. 한 OS에만 추가하면 세 환경이 조용히 어긋난다.
- 문서·주석·로그는 한국어, 비개발자 팀원도 읽는다는 전제로 작성한다.
- 스크립트는 멱등해야 한다: 설치 전 존재 확인, 실패 시 경고 후 건너뛰고 계속 진행.

## 대상 환경 (확정 · 임의로 넓히지 말 것)

- **Ubuntu 22.04 LTS 이상 / Debian 12 이상 데스크톱.** x86_64(amd64)·ARM64 둘 다.
- WSL 전용 분기를 넣지 않는다 — WSL 사용자는 co-win 을 쓴다.
- Fedora(dnf)·Arch(pacman) 분기를 넣지 않는다. 다른 배포판은 헤더에서 경고만 하고 계속 진행한다.
- **Homebrew on Linux 와 flatpak 은 쓰지 않는다.** 패키지는 apt(주) + snap(보조) + 공식 .deb 저장소로 통일한다.

## bash 스크립트 규칙 (맥·윈도우 스크립트와 다른 부분)

- **절대 스크립트를 중단시키지 않는다.** `set -e` 하에서 모든 설치는 `|| warn "... → 건너뜀"` 로 받는다. `exit` 는 옵션 파싱·모드 충돌·apt 부재 확인 세 곳에서만 쓴다.
- **`set -u` 와 `set -o pipefail` 을 쓰지 않는다** (mac-setup.sh 와 동일). 이 규모의 스크립트에서는 선택적 변수 하나가 비어 있다는 이유로 전체가 죽는 사고가 더 잦다.
- **공통 헬퍼만 쓴다** — 파일 상단에 정의돼 있다. 재정의하지 말 것:
  `log` / `have` / `ok` / `warn` / `info` / `apt_install` / `apt_refresh` / `is_installed` /
  `snap_install` / `add_apt_repo` / `install_deb` / `need_sudo` / `path_prepend` /
  `op_has_account` / `op_read` / `copy_dotfile`
  그리고 변수 `SUDO` / `ARCH` / `HAS_GUI` / `DISTRO_ID` / `DISTRO_CODENAME` / `SCRIPT_DIR` / `STANDALONE`
- **스크립트 전체를 `sudo` 로 돌리게 만들지 않는다.** fvm·`dart pub global`·nvm·pyenv 설치물이 전부 `/root` 밑에 깔려 평소 터미널에서 안 보이는 2차 사고가 난다. 관리자 권한이 필요한 작업은 `need_sudo` 로 확인하고, 없으면 **명령어와 함께 방법만 안내하고 건너뛴다**.
- **`apt-key` 를 쓰지 않는다.** 우분투 22.04부터 폐지 예고 상태다. 저장소는 `add_apt_repo` 헬퍼(= `/etc/apt/keyrings` + `signed-by`)로만 등록한다.
- **`apt-get` 은 항상 `DEBIAN_FRONTEND=noninteractive` 와 `-y` 를 붙인다.** 설정 파일 충돌 대화창이 뜨면 스크립트가 그 자리에서 멈춘 것처럼 보인다.
- **비밀값은 파일에 쓰지 않는다.** 1Password 에서 읽은 토큰은 메모리 파이프로만 넘기고(`gh auth login --with-token`), 쓰고 나서 반드시 `unset` 한다. `~/.zshrc` 에 주입하는 팀 공용 토큰만 예외다.
- **파일은 UTF-8(BOM 없음) + LF** 로 저장한다. BOM 이 붙으면 `#!` 앞에 바이트가 끼어 실행이 실패한다.
- **경로를 하드코딩하지 않는다.** JDK 는 아키텍처별로 `/usr/lib/jvm/java-17-openjdk-<arch>` 라 glob 으로 찾고, Android SDK 는 리눅스 표준인 `$HOME/Android/Sdk` 를 쓴다(맥의 `~/Library/Android/sdk` 아님).

## 수정 후 검증

문법 오류는 눈으로 잡히지 않는다. 고친 뒤에는 반드시 셋 다 돌린다.

```bash
bash -n linux-setup.sh                                  # 문법
shellcheck -S warning linux-setup.sh                    # 정적 분석 (brew install shellcheck)
file linux-setup.sh && head -c 3 linux-setup.sh | xxd   # UTF-8 BOM 이 없어야 한다
```

실제 우분투에서 돌려보려면 도커를 쓴다 (맥에서 작업 중이어도 된다):

```bash
docker run --rm -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash -c "apt-get update -qq && apt-get install -y -qq sudo curl >/dev/null && bash -n linux-setup.sh && echo 'PARSE OK'"
```
