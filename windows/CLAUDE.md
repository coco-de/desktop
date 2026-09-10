# co-win

새 윈도우 PC를 co:code 팀 표준 개발환경으로 세팅하는 스크립트 레포. 핵심 파일은 `win-setup.ps1`(설치 스크립트)와 `README.md`(문서) 둘뿐이며, 두 파일은 항상 같은 내용을 가리켜야 한다.

**형제 레포: [coco-de/co-mac](https://github.com/coco-de/co-mac)** — 같은 도구 목록을 macOS 방식으로 설치한다. 팀 표준 도구가 바뀌면 **두 레포를 함께 갱신해야 한다.**

## 필수 규칙

- **`win-setup.ps1`에서 도구를 추가/삭제/변경할 때는 반드시 `sync-tool-docs` 스킬을 사용해** README.md와 스크립트 내 log/주석/검증 문구를 함께 갱신한다. 코드만 고치고 문서를 남겨두면 안 된다.
- **co-mac과의 대응 관계를 항상 확인한다.** 도구를 추가하면 맥에도 있는지, 빠뜨렸다면 왜인지를 README의 `🍎 맥과 무엇이 다른가요` 섹션에 남긴다. 맥에만 추가하고 윈도우를 빼먹으면 두 환경이 조용히 어긋난다.
- 문서·주석·로그는 한국어, 비개발자 팀원도 읽는다는 전제로 작성한다.
- 스크립트는 멱등해야 한다: 설치 전 존재 확인, 실패 시 경고 후 건너뛰고 계속 진행.

## PowerShell 스크립트 규칙 (맥 스크립트와 다른 부분)

- **절대 스크립트를 중단시키지 않는다.** `$ErrorActionPreference = 'Continue'` 가 기본이고, `throw` 를 쓰지 않으며, `exit` 는 모드 분기(`-Help`·옵션 충돌·`-DartOnly` 사전 점검·PowerShell 7 재실행) 네 곳에서만 쓴다. 각 단계는 `try/catch` 로 감싸고 `catch` 에서 `Write-Warn` 한다.
- **Windows PowerShell 5.1에서도 파싱은 돼야 한다.** 삼항 연산자(`a ? b : c`), null 병합(`??`), 파이프라인 체인(`&&`·`||`), `$PSStyle` 금지. 실행은 PowerShell 7 전제이며, 5.1에서 시작하면 스크립트가 pwsh를 설치하고 스스로 다시 시작한다.
- **파일은 UTF-8 BOM으로 저장한다.** BOM이 없으면 Windows PowerShell 5.1이 파일을 ANSI(CP949)로 읽어 한글 주석과 안내 문구가 전부 깨진다.
- **공통 헬퍼만 쓴다** — 파일 상단에 정의돼 있다. 재정의하지 말 것:
  `Write-Step` / `Write-Ok` / `Write-Warn` / `Write-Info` / `Test-Cmd` / `Test-Admin` / `Test-Interactive` /
  `Add-UserPath` / `Set-UserEnv` / `Install-Winget` / `Install-Scoop` / `Test-OpAccount` / `Get-OpSecret`
- **PATH·환경변수는 `Add-UserPath`·`Set-UserEnv` 로만 건드린다.** `setx` 는 값을 1024자에서 잘라 PATH를 통째로 날리므로 절대 쓰지 않는다. 두 헬퍼는 레지스트리(영구)와 현재 세션 양쪽에 반영한다.
- **관리자 권한이 필요한 작업은 `Test-Admin` 으로 확인하고, 없으면 방법만 안내하고 건너뛴다.** 스크립트 전체를 관리자로 돌리게 만들면 winget·fvm·pub 설치물이 관리자 프로필 경로에 깔려 평소 터미널에서 안 보이는 2차 사고가 난다.
- **비밀값은 파일에 쓰지 않는다.** PowerShell 프로필은 '문서' 폴더에 있어 OneDrive로 동기화되므로, 토큰은 반드시 사용자 환경변수(`Set-UserEnv`)에만 넣는다.
- **경로는 `Join-Path` 또는 `$env:LOCALAPPDATA\...` 형태로 쓴다.** `C:\Users\...` 하드코딩 금지. 프로필 경로는 `$PROFILE.CurrentUserAllHosts` 에서 읽는다(OneDrive 리디렉션 대응).
- **`npx` 로 뜨는 MCP 서버는 `cmd /c npx ...` 로 감싸 등록한다.** 감싸지 않으면 `claude mcp list` 에는 멀쩡히 보이는데 연결만 조용히 실패한다.
- **`${VAR}` 리터럴은 반드시 작은따옴표로 넘긴다.** 큰따옴표를 쓰면 그 자리에서 빈 문자열로 확장돼 저장되고, 등록은 성공한 것처럼 보이지만 인증만 실패한다.

## 수정 후 검증

문법 오류는 눈으로 잡히지 않는다. 고친 뒤에는 PowerShell 파서로 확인한다.

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('win-setup.ps1', [ref]$null, [ref]$errors)
$errors
```

맥에서 작업 중이라면 도커로 같은 검사를 돌릴 수 있다.

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/work" mcr.microsoft.com/powershell:latest \
  pwsh -NoProfile -c "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('/work/win-setup.ps1',[ref]\$null,[ref]\$e); \$e"
```
