# ============================================================
# 윈도우 초기 개발환경 세팅 스크립트 (co:code 팀 표준)
#
# 전제: 없음 — winget(앱 설치 관리자)과 Scoop은 이 스크립트가 0단계에서 자동으로 설치한다.
#       맥 스크립트(macos/mac-setup.sh)와 같은 도구를 같은 순서로 깔며,
#       윈도우에 없는 항목(Xcode·CocoaPods 등)만 빠지고 윈도우 전용 항목이 대신 들어간다.
#
# 실행 (레포를 clone한 경우):
#   PowerShell 창에서
#     Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
#     .\win-setup.ps1
#
# 실행 (clone 없이 한 줄로):
#   Set-ExecutionPolicy -Scope Process Bypass -Force; $s="$env:TEMP\win-setup.ps1"; iwr -UseBasicParsing https://raw.githubusercontent.com/coco-de/desktop/main/windows/win-setup.ps1 -OutFile $s; Unblock-File $s; & $s
#   └ 맨 앞의 Set-ExecutionPolicy 는 **지금 열려 있는 이 창에만** 적용된다(창을 닫으면 원래대로).
#     이게 없으면 새 PC 기본값(Restricted)에서 파일은 내려받아지지만 실행이 막힌다.
#   └ 이 경우 스크립트 파일 하나만 내려오므로, 팀 셸 설정(PowerShell 프로필)은
#     7단계(PowerShell 프로필 설정)에서 이 스크립트가 직접 만들어 준다.
#   └ 옵션도 그대로 붙일 수 있다:  & $s -EnvOnly
#
#   ⚠ `irm ... | iex` 형태는 "옵션을 붙일 수 없다"는 한계가 있어 위 방식을 권장한다.
#      (iex 는 인자를 받지 못해 -EnvOnly 같은 옵션이 통째로 무시된다 — 맥 스크립트에서
#       `--` 를 빠뜨려 수십 분짜리 전체 설치가 조용히 시작되던 것과 똑같은 사고다.)
#
# 기존 PC의 설정을 그대로 가져오려면, 기존 PC에서
#   $PROFILE.CurrentUserAllHosts 파일(Profile.ps1)
# 을 이 스크립트와 같은 폴더에 Profile.ps1 이름으로 복사해 두세요.
# (프로필이 아직 없는 PC라면 7단계에서 그 파일을 프로필의 출발점으로 삼습니다)
# ============================================================

# ⚠ param 블록은 스크립트에서 (주석을 뺀) 첫 번째 문장이어야 한다 — 위치를 옮기지 말 것.
param(
    # 1Password(op)에서 팀 공용 토큰만 다시 읽어 사용자 환경변수에 주입 (8.5단계만)
    [switch]$EnvOnly,
    # Dart 글로벌 패키지만 다시 설치/업데이트 (4-b단계만)
    [switch]$DartOnly,
    # 윈도우 시스템 설정(개발자 모드·긴 경로·브라우저 확장)만 다시 실행 (1.5단계만)
    [switch]$SystemOnly,
    # Windows Defender 실시간 검사에서 빌드 캐시 폴더를 제외한다 (기본 꺼짐 — 보안 담당자 승인 후에만)
    [switch]$DefenderExclusions,
    # 안드로이드 에뮬레이터 가속(Windows Hypervisor Platform)을 실제로 켠다 (기본은 진단만)
    [switch]$EnableHyperV,
    # PowerShell 7로 다시 실행하지 않는다 (문제 진단용 — 평소에는 쓰지 않는다)
    [switch]$NoReExec,
    [switch]$Help
)

# ------------------------------------------------------------
# 전역 실행 방침
#
#   맥 스크립트의 `set -e`(오류 시 즉시 중단)와 **정반대**로 잡는다.
#   이 스크립트의 약속은 "도구 하나가 안 깔려도 나머지 서른 개는 깔린다" 이므로,
#   기본값을 Continue로 두고 각 단계가 자기 실패를 스스로 처리한다.
#   (맥 쪽은 단계마다 `|| echo "⚠ ..."` 를 붙여 같은 효과를 낸다)
#
#   $ProgressPreference = 'SilentlyContinue' 는 취향 문제가 아니다 —
#   Invoke-WebRequest 의 진행률 막대는 윈도우에서 다운로드를 몇 배 느리게 만든다.
# ------------------------------------------------------------
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# 한글이 깨지지 않게 콘솔 출력 인코딩을 UTF-8로 맞춘다.
#   윈도우 기본 콘솔은 아직 CP949라, 이 줄이 없으면 이 스크립트의 안내 문구가
#   전부 물음표·깨진 글자로 보인다. 실패해도 무해하므로 조용히 넘긴다.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# 낡은 통신 규격(TLS 1.0/1.1)만 켜진 PC에서 다운로드가 통째로 실패하는 것을 막는다.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# 이 레포의 원본 파일 주소 — 메모리 실행(iex)으로 시작해 다시 실행할 파일이 없을 때
# 이 스크립트를 임시 폴더로 내려받는 데 쓴다.
$RepoRawBase = 'https://raw.githubusercontent.com/coco-de/desktop/main/windows'

# ------------------------------------------------------------
# 실행 방식 감지 — 파일로 실행했나, 메모리에서 바로 실행했나
#
#   파일로 실행하면 $PSScriptRoot 에 그 폴더 경로가 들어온다.
#   `iex` 로 메모리에서 실행하면 **빈 문자열**이 된다.
#
#   [왜 이걸 구분하나 — 맥 스크립트에서 사고가 났던 지점이다]
#   빈 값을 "지금 터미널이 열려 있는 폴더"로 착각하면, 홈 폴더에 이미 있던 설정 파일을
#   "사용자가 스크립트 옆에 놓아둔 팀 설정"으로 오인해 엉뚱한 파일을 복사하게 된다.
#   → 옆 폴더라는 개념 자체가 없는 실행 방식이므로, 추측하지 말고 없다고 명시한다.
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptDir = ''
    $Standalone = $true    # 메모리 실행 — 옆에 놓인 파일이 없다고 본다
} else {
    $ScriptDir = $PSScriptRoot
    $Standalone = $false
}

# ------------------------------------------------------------
# 사용법
# ------------------------------------------------------------
function Show-Usage {
    Write-Host @'
사용법: .\win-setup.ps1 [옵션]

  (옵션 없음)   co:code 팀 표준 개발환경 전체 설치 (0~10단계)
                winget·Scoop이 없으면 0단계에서 자동으로 설치합니다.
                OpenCode·Claude Code에 기본 MCP 10개를 함께 등록합니다(6.6단계).
  -EnvOnly      1Password(op)에서 팀 공용 토큰(ZENHUB_API_TOKEN·JIRA_API_TOKEN·
                SLANG_GPT_API_KEY·DCM_EMAIL·DCM_CI_KEY·SLACK_TEAM_ID·
                SLACK_BOT_TOKEN·TYPESAFE_API_KEY·OPENAI_API_KEY)만 다시 읽어
                윈도우 사용자 환경변수에 주입합니다.
                앱/도구 설치 단계는 전부 건너뜁니다.
                (토큰이 바뀌었거나, 설치 때 토큰 주입을 건너뛴 경우에 사용)
  -DartOnly     Dart 글로벌 패키지(coverage·melos·mason_cli·flutter_gen·
                jaspr_cli·serverpod_cli·flutterfire_cli·marionette_mcp·
                mcp_server_dart·cob)만 다시 설치/업데이트합니다.
                (팀 패키지 목록이 바뀌었거나, 패키지만 최신으로 올리고 싶을 때 사용
                 — Flutter/Dart(fvm)는 이미 설치돼 있어야 합니다)
  -SystemOnly   윈도우 시스템 설정만 다시 점검합니다 — 개발자 모드(심볼릭 링크 허용),
                긴 경로 허용, 브라우저 확장·번역 설정.
                (설치 때 관리자 권한이 없어 건너뛴 항목을 나중에 마저 켤 때 사용
                 — 관리자 권한으로 실행해야 실제로 적용됩니다)
  -DefenderExclusions
                pub 캐시·Gradle·Android SDK 폴더를 Windows Defender 실시간 검사에서
                제외해 빌드 속도를 올립니다. **기본은 꺼져 있습니다** — 그 폴더가 곧
                외부 코드가 떨어지는 곳이라, 보안 담당자와 상의한 뒤에만 쓰세요.
                (관리자 권한 필요 · 되돌리기: Remove-MpPreference -ExclusionPath <경로>)
  -EnableHyperV 안드로이드 에뮬레이터 가속(Windows Hypervisor Platform)을 실제로 켭니다.
                기본값은 상태 진단과 안내까지만 합니다 — 이 기능을 켜면 재부팅이
                필요하고 일부 VM 소프트웨어와 충돌할 수 있기 때문입니다.
                이 옵션만 붙여 실행하면 전체 설치 없이 가속만 켜고 끝냅니다.
                (관리자 권한 필요 · 켠 뒤 재부팅해야 적용됩니다)
  -NoReExec     PowerShell 7로 다시 실행하지 않고 지금 셸에서 그대로 진행합니다
                (문제 진단용 — 평소에는 쓰지 않습니다)
  -Help         이 도움말을 표시합니다

  ※ -DefenderExclusions 는 '윈도우 시스템 설정' 단계와 함께 동작합니다. 단독으로 써도
    전체 설치(0~10단계)는 시작되지 않고 시스템 설정 단계만 돕니다. -SystemOnly 와 함께 써도 됩니다.
  ※ -EnableHyperV 를 단독으로 쓰면 전체 설치 없이 '가속만' 켜고 끝냅니다(관리자 권한 필요).
    옵션 없이 전체 설치를 돌릴 때 함께 붙이면 안드로이드 SDK 단계에서 같은 일을 합니다.
'@
}

if ($Help) { Show-Usage; exit 0 }

# 모드 옵션들은 하는 일이 서로 달라 함께 쓰면 어느 쪽을 원한 건지 알 수 없다 —
# 조용히 한쪽만 실행하지 말고 무엇을 골라야 하는지 알려주고 멈춘다.
# (옵션이 하나 늘 때마다 조건을 새로 조합하지 않도록 개수로 센다)
$ModeCount = 0
if ($EnvOnly) { $ModeCount++ }
if ($DartOnly) { $ModeCount++ }
if ($SystemOnly) { $ModeCount++ }
if ($ModeCount -gt 1) {
    Write-Host '❌ -EnvOnly · -DartOnly · -SystemOnly 는 하나만 쓸 수 있습니다.' -ForegroundColor Red
    Write-Host ''
    Show-Usage
    exit 1
}

# 이 세 값이 아래 모든 단계의 실행 여부를 가른다.
#   $RunInstall : 설치 단계 전체 (모드 옵션도 추가 동작 옵션도 하나도 없을 때만)
#   -DefenderExclusions / -EnableHyperV 만 붙여 실행한 사람은 '그 설정만' 하려던 것이지
#   30분~2시간짜리 전체 설치를 원한 게 아니다 — 이 두 옵션이 있으면 전체 설치를 켜지 않는다.
$RunInstall = ($ModeCount -eq 0 -and -not $DefenderExclusions -and -not $EnableHyperV)

# -EnableHyperV 만 붙여 실행하면 '에뮬레이터 가속만 켜 달라'는 뜻이다 — 30분짜리 전체 설치를
# 다시 돌릴 필요 없이 여기서 바로 처리하고 끝낸다. (전체 설치로 실행하면 4-e 안드로이드 단계가
# 같은 일을 하므로 이 블록은 건너뛴다.)
# ⚠ Write-Warn·Test-Admin 은 아래에서 정의되므로 여기서는 직접 판정하고 Write-Host 를 쓴다.
if ($EnableHyperV -and -not $RunInstall) {
    $HvIsAdmin = $false
    try {
        $HvId = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $HvPrincipal = New-Object System.Security.Principal.WindowsPrincipal($HvId)
        $HvIsAdmin = $HvPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $HvIsAdmin = $false }

    Write-Host ''
    Write-Host '▶ 안드로이드 에뮬레이터 가속(Windows Hypervisor Platform) 켜기' -ForegroundColor Cyan
    if ($HvIsAdmin) {
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart -ErrorAction Stop | Out-Null
            Write-Host '  ✓ 가속을 켰습니다 — PC를 다시 시작해야 적용됩니다' -ForegroundColor Green
            Write-Host '  · 재부팅 후에도 에뮬레이터가 안 뜨면 BIOS/UEFI 에서 가상화(Intel VT-x / AMD SVM)가 꺼져 있는 경우입니다' -ForegroundColor DarkGray
        } catch {
            Write-Host "  ⚠ 가속 켜기 실패 → 건너뜀 (수동: DISM /Online /Enable-Feature /FeatureName:HypervisorPlatform /All /NoRestart) — $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host '  ⚠ 이 작업에는 관리자 권한이 필요합니다 → 건너뜀' -ForegroundColor Yellow
        Write-Host '     시작 메뉴에서 PowerShell 을 오른쪽 클릭 > "관리자 권한으로 실행" 한 뒤 다시 실행해 주세요:' -ForegroundColor Yellow
        Write-Host '       .\win-setup.ps1 -EnableHyperV' -ForegroundColor Yellow
    }
}

# ============================================================
# 공통 헬퍼 — 모든 단계가 이 함수들만 쓴다
#   (맥 스크립트의 log / have / brew 설치 래퍼에 해당한다)
# ============================================================

# 단계 배너. 맥의 `log() { echo ""; echo "▶ $1"; }` 와 1:1 대응.
function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "▶ $Message" -ForegroundColor Cyan
}

function Write-Ok   { param([string]$Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "  ⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "  · $Message" -ForegroundColor DarkGray }

# 명령이 실제로 존재하는지 (맥의 have)
function Test-Cmd {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    try { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) } catch { return $false }
}

# 관리자(상승) 권한으로 실행 중인가 (맥의 sudo 가능 여부에 해당)
function Test-Admin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# 사람이 보고 있는 창에서 실행 중인가 (맥의 `[[ -t 0 ]]`)
#   비대화형(CI·예약 작업)에서는 입력을 기다리는 단계를 전부 건너뛰어야 한다.
function Test-Interactive {
    try {
        if ([Environment]::UserInteractive -ne $true) { return $false }
        # 입력이 파일·NUL·파이프로 연결돼 있으면(CI 러너 · Intune 배포 · pwsh -File ... < NUL)
        # 사람이 답할 수 없다. 맥의 [[ -t 0 ]] 에 해당하는 진짜 검사로, 이게 없으면
        # Read-Host 가 빈 값을 즉시 돌려주며 같은 질문을 끝없이 반복하는 무한 루프가 된다.
        if ([Console]::IsInputRedirected) { return $false }
        if ($null -eq $Host.UI -or $null -eq $Host.UI.RawUI) { return $false }
        return $true
    } catch { return $false }
}

# ------------------------------------------------------------
# 사용자 PATH 영구 추가
#
#   [왜 setx 를 쓰지 않나 — 여기서 PC를 망가뜨릴 수 있다]
#   setx 는 값을 1024자에서 **잘라 버린다**. 개발 PC의 PATH는 금방 그 길이를 넘기므로
#   setx 한 번에 PATH 절반이 사라지고, 그때부터 아무 명령도 안 잡힌다.
#   그래서 레지스트리를 직접 읽고 쓴다.
#
#   [왜 GetValue 에 DoNotExpandEnvironmentNames 를 주나]
#   사용자 PATH에는 보통 `%USERPROFILE%\...` 같은 자리표시자가 들어 있다. 그냥 읽으면
#   그 자리가 실제 경로로 펼쳐진 채 저장돼, 계정 이름이 바뀌면 통째로 깨진다.
#   원본 형태(REG_EXPAND_SZ)를 그대로 보존해서 다시 쓴다.
#
#   현재 열려 있는 이 창의 PATH에도 즉시 반영한다 — 그래야 같은 실행 안의 다음 단계가
#   방금 깐 도구를 바로 찾을 수 있다(윈도우는 열린 창의 PATH를 스스로 갱신하지 않는다).
# ------------------------------------------------------------
function Add-UserPath {
    param(
        [string]$Dir,
        [switch]$Front
    )

    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    # 비교는 '펼친 절대경로'끼리 해야 한다 — 사용자 PATH에는 %USERPROFILE%\... 같은
    # 자리표시자가 그대로 들어 있어서, 펼치지 않으면 같은 폴더를 다른 값으로 보고 또 붙인다.
    $normalized = ([Environment]::ExpandEnvironmentVariables($Dir)).TrimEnd('\')

    # ① 지금 이 창에 즉시 반영
    try {
        $sessionParts = @()
        foreach ($p in ($env:PATH -split ';')) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            if (([Environment]::ExpandEnvironmentVariables($p)).TrimEnd('\') -ieq $normalized) { continue }
            $sessionParts += $p
        }
        if ($Front) { $env:PATH = (@($Dir) + $sessionParts) -join ';' }
        else        { $env:PATH = ($sessionParts + @($Dir)) -join ';' }
    } catch { }

    # ② 사용자 환경변수(레지스트리)에 영구 반영
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        if ($null -eq $key) { return }
        try {
            $current = ''
            $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
            if (@($key.GetValueNames()) -contains 'Path') {
                $current = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $kind = $key.GetValueKind('Path')
            }

            $parts = @()
            foreach ($p in ($current -split ';')) {
                if ([string]::IsNullOrWhiteSpace($p)) { continue }
                if (([Environment]::ExpandEnvironmentVariables($p)).TrimEnd('\') -ieq $normalized) { continue }
                $parts += $p
            }
            if ($Front) { $new = (@($Dir) + $parts) -join ';' }
            else        { $new = ($parts + @($Dir)) -join ';' }

            # 사용자 PATH가 2047자를 넘으면 윈도우가 조용히 잘라내기 시작한다 —
            # 그 전에 멈추고 사람에게 정리를 부탁한다.
            # 단, '이미 등록돼 있어 바뀔 게 없는' 경우까지 경고하면 재실행 때마다 헛경고가
            # 쏟아지므로, 실제로 새로 써야 할 때만 길이를 검사한다.
            if (($new -ne $current) -and ($new.Length -ge 2047)) {
                Write-Warn "사용자 PATH가 너무 길어 '$Dir' 추가를 건너뜁니다 (환경 변수 편집기에서 안 쓰는 경로를 정리한 뒤 다시 실행해 주세요)"
                return
            }
            if ($new -ne $current) {
                $key.SetValue('Path', $new, $kind)
            }
        } finally {
            $key.Close()
        }
    } catch {
        Write-Warn "사용자 PATH 갱신 실패($Dir) → 건너뜀 (수동: 시스템 환경 변수 편집에서 직접 추가)"
    }
}

# 사용자 환경변수 영구 설정 + 지금 이 창에도 즉시 반영.
#   값이 $null 이거나 빈 문자열이면 변수를 지운다.
function Set-UserEnv {
    param(
        [string]$Name,
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    try {
        if ([string]::IsNullOrEmpty($Value)) {
            [Environment]::SetEnvironmentVariable($Name, $null, 'User')
            [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
            [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
        }
        return $true
    } catch {
        Write-Warn "환경변수 $Name 설정 실패 → 건너뜀 (수동: 시스템 환경 변수 편집에서 직접 추가)"
        return $false
    }
}

# winget이 그 패키지를 이미 깔아 뒀는지 확인 (맥의 `brew list <pkg>`)
function Test-WingetInstalled {
    param([string]$Id)
    if (-not (Test-Cmd 'winget')) { return $false }
    try {
        # winget list 는 표 형식이라 창이 좁으면 Id 열을 '…' 로 잘라 버린다 — 출력 문자열로
        # 판정하면 긴 ID(예: zhongyang219.TrafficMonitor.Full)가 이미 설치돼 있어도 '미설치'로
        # 보인다. 그래서 종료 코드로만 판정한다
        # (찾으면 0, 못 찾으면 APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND).
        & winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        return $true
    } catch { return $false }
}

# ------------------------------------------------------------
# winget 멱등 설치 (맥의 install_cask / brew install 자리)
#   설치됐으면 $true, 실패했으면 $false 를 돌려준다. **절대 스크립트를 멈추지 않는다.**
#
#   -ProbeCmd  : 이 명령이 이미 있으면 설치를 건너뛴다 (예: 'git')
#   -ProbePath : 이 경로가 이미 있으면 설치를 건너뛴다 (앱처럼 명령이 없는 경우)
#   -Scope     : user 또는 machine. 지정하지 않으면 winget 기본값
#   -Override  : 설치 프로그램에 넘길 인자를 '통째로 대체'한다.
#                ⚠ winget이 기본으로 넣어 주는 무인 설치 스위치까지 사라지므로,
#                  이걸 쓸 때는 조용히 설치되는 옵션(/VERYSILENT 등)을 직접 다 적어야 한다.
#   -Custom    : 설치 프로그램에 넘길 인자를 기본 무인 설치 스위치 '뒤에 덧붙인다'.
#                옵션만 얹고 싶을 때는 -Override 말고 이쪽을 쓴다(설치 마법사 창이 뜨지 않는다).
# ------------------------------------------------------------
function Install-Winget {
    param(
        [string]$Id,
        [string]$Name = '',
        [string]$ProbeCmd = '',
        [string]$ProbePath = '',
        [string]$Scope = '',
        [string]$Override = '',
        [string]$Custom = '',
        [string]$Source = 'winget'
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $Id }

    if ($ProbeCmd -and (Test-Cmd $ProbeCmd)) { Write-Ok "$Name 이미 설치됨"; return $true }
    if ($ProbePath -and (Test-Path -LiteralPath $ProbePath -ErrorAction SilentlyContinue)) {
        Write-Ok "$Name 이미 설치됨"
        return $true
    }

    if (-not (Test-Cmd 'winget')) {
        Write-Warn "winget이 없어 $Name 설치를 건너뜁니다 (수동 설치: Microsoft Store에서 '앱 설치 관리자' 설치 후 재실행)"
        return $false
    }

    if (Test-WingetInstalled $Id) { Write-Ok "$Name 이미 설치됨 (winget)"; return $true }

    # ⚠ $args 는 PowerShell 예약 변수라 함수 안에서 덮어쓰면 안 된다 — 다른 이름을 쓴다.
    $wingetArgs = @(
        'install', '--id', $Id, '--exact',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )
    if ($Source)   { $wingetArgs += @('--source', $Source) }
    if ($Scope)    { $wingetArgs += @('--scope', $Scope) }
    if ($Override) { $wingetArgs += @('--override', $Override) }
    if ($Custom)   { $wingetArgs += @('--custom', $Custom) }

    try {
        & winget @wingetArgs 2>&1 | Out-Null
        $code = $LASTEXITCODE
    } catch {
        $code = -1
    }

    # winget은 "이미 최신"·"업그레이드 대상 아님" 같은 경우에도 0이 아닌 코드를 낸다.
    # 그래서 종료 코드만 보고 실패로 단정하지 않고, 실제로 깔렸는지 다시 확인한다
    # (맥 스크립트가 인스톨러 종료 코드 대신 바이너리 존재로 판정하는 것과 같은 이유).
    $installed = $false
    if ($ProbeCmd -and (Test-Cmd $ProbeCmd)) { $installed = $true }
    if (-not $installed -and $ProbePath -and (Test-Path -LiteralPath $ProbePath -ErrorAction SilentlyContinue)) { $installed = $true }
    if (-not $installed -and (Test-WingetInstalled $Id)) { $installed = $true }

    if ($installed) {
        Write-Ok "$Name 설치 완료"
        return $true
    }

    if ($code -eq -1978335189) {
        # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE — 이미 최신이라는 뜻이므로 성공으로 본다
        Write-Ok "$Name 이미 최신 상태"
        return $true
    }

    Write-Warn "$Name 설치 실패 → 건너뜀 (수동 설치: winget install --id $Id --exact)"
    return $false
}

# Scoop 멱등 설치 — winget에 없는 CLI 도구용 (맥의 brew formula 자리 일부)
function Install-Scoop {
    param(
        [string]$Package,
        [string]$Name = '',
        [string]$Bucket = '',
        [string]$ProbeCmd = ''
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $Package }

    if ($ProbeCmd -and (Test-Cmd $ProbeCmd)) { Write-Ok "$Name 이미 설치됨"; return $true }

    if (-not (Test-Cmd 'scoop')) {
        Write-Warn "Scoop이 없어 $Name 설치를 건너뜁니다 (수동 설치: 0.5단계 안내 참고)"
        return $false
    }

    try {
        $listed = (& scoop list 2>&1 | Out-String)
        if ($listed -match ("(?m)^\s*" + [regex]::Escape($Package) + "\s")) {
            Write-Ok "$Name 이미 설치됨 (Scoop)"
            return $true
        }
    } catch { }

    if ($Bucket) {
        try {
            $buckets = (& scoop bucket list 2>&1 | Out-String)
            if ($buckets -notmatch [regex]::Escape($Bucket)) {
                & scoop bucket add $Bucket 2>&1 | Out-Null
            }
        } catch {
            Write-Info "Scoop 버킷 '$Bucket' 추가에 실패했지만 설치는 계속 시도합니다"
        }
    }

    $target = $Package
    if ($Bucket) { $target = "$Bucket/$Package" }

    try {
        & scoop install $target 2>&1 | Out-Null
    } catch { }

    if ($ProbeCmd -and (Test-Cmd $ProbeCmd)) {
        Write-Ok "$Name 설치 완료 (Scoop)"
        return $true
    }
    try {
        $listed2 = (& scoop list 2>&1 | Out-String)
        if ($listed2 -match ("(?m)^\s*" + [regex]::Escape($Package) + "\s")) {
            Write-Ok "$Name 설치 완료 (Scoop)"
            return $true
        }
    } catch { }

    Write-Warn "$Name 설치 실패 → 건너뜀 (수동 설치: scoop install $target)"
    return $false
}

# ------------------------------------------------------------
# 1Password 팀 계정 · 비밀값 읽기
#
#   3.4단계(GitHub 인증 자동화)와 8.5단계(팀 토큰 주입)가 함께 쓴다.
#   가장 먼저 쓰는 단계보다 앞에 두어야 해서 여기 둔다.
#
#   ⚠ 계정이 등록되지 않은 상태의 op는 "계정을 지금 추가할까요? [Y/n]" 를 물으며
#     입력을 기다린다. 그대로 두면 스크립트가 거기서 멈춰 버리므로, 값을 읽기 전에
#     반드시 계정 등록 여부부터 확인한다.
#     (`op account list`는 계정이 하나도 없어도 종료 코드 0에 빈 목록만 내므로,
#      종료 코드가 아니라 '출력 내용'으로 판단해야 한다 — 맥 쪽과 같은 함정이다)
# ------------------------------------------------------------
$TeamOpAccount = 'team-cocodeinc.1password.com'   # 팀 1Password 계정 (비밀 아님)

function Test-OpAccount {
    if (-not (Test-Cmd 'op')) { return $false }
    try {
        $out = (& op account list 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { return $false }
        $trimmed = $out.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }
        if ($trimmed -eq '[]') { return $false }
        return $true
    } catch { return $false }
}

# op read 래퍼. 값을 못 읽으면 $null 을 돌려준다 (절대 멈추지 않는다).
function Get-OpSecret {
    param([string]$Ref)
    if ([string]::IsNullOrWhiteSpace($Ref)) { return $null }
    if (-not (Test-OpAccount)) { return $null }
    try {
        $val = (& op read --account $TeamOpAccount $Ref 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0) { return $null }
        $val = $val.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) { return $null }
        return $val
    } catch { return $null }
}

# ------------------------------------------------------------
# 팀 표준 Flutter 버전
#
#   4-a단계가 fvm 으로 이 버전을 설치하고 기본(global) 버전으로 고정한다.
#   'stable' 채널을 따라가면 PC마다 설치한 날의 최신판이 깔려 팀원끼리 버전이 어긋나므로
#   숫자로 못 박는다. 4-a보다 먼저 실행되는 -DartOnly 안내와 10단계 설치 검증도 이 값을
#   쓰므로 여기 둔다.
#   버전을 올릴 때는 맥·리눅스 스크립트의 같은 값과 세 README 의 Flutter 버전 표기를 함께 바꾼다.
# ------------------------------------------------------------
$TeamFlutterVersion = '3.47.6'

# ------------------------------------------------------------
# CPU 종류 판정 — 이 PC가 ARM64(Snapdragon X 등)인가
#
#   ⚠ $env:PROCESSOR_ARCHITECTURE 만 보면 안 된다. ARM64 노트북에서 PowerShell이
#     x64 호환 모드로 뜨면 'AMD64'라고 거짓으로 답한다. 그래서 윈도우가 직접 보고하는
#     하드웨어 정보(CIM: Win32_ComputerSystem · Win32_Processor)를 먼저 본다.
#     (Win32_Processor.Architecture 값 12 = ARM64)
#   0단계 winget 의존성 · 1단계 GUI 앱 · fvm · DCM · 안드로이드가 모두 이 값을 쓰므로,
#   실행 모드와 무관하게 여기서 한 번만 계산한다.
# ------------------------------------------------------------
$ArchIsArm64 = $false
$CpuArch = ''
try {
    $ArchSysType = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).SystemType
    $ArchCpuCode = (Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Architecture
    if ($ArchSysType) { $CpuArch = [string]$ArchSysType }
    if (($CpuArch -match 'ARM64') -or ($ArchCpuCode -eq 12)) { $ArchIsArm64 = $true }
} catch { }
# CIM을 쓸 수 없는 PC(WMI 서비스가 꺼져 있는 등)에서만 환경변수로 대신한다.
# 32비트 PowerShell로 실행됐을 때를 대비해 PROCESSOR_ARCHITEW6432도 함께 본다.
if ([string]::IsNullOrWhiteSpace($CpuArch)) {
    $CpuArch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $CpuArch = $env:PROCESSOR_ARCHITEW6432 }
    if ($CpuArch -eq 'ARM64') { $ArchIsArm64 = $true }
}

# ============================================================
# 실행 단계 맵 (맥 스크립트의 단계 번호를 그대로 따라간다)
#   사전. PowerShell 7 준비 — 윈도우 PowerShell 5.1로 시작했을 때만 나오는 사전 단계
#        (pwsh 를 깔고 그쪽에서 스스로 다시 시작한다)
#   0.   winget(앱 설치 관리자) — 없으면 3단 폴백으로 자동 설치
#   0.5. Scoop — winget에 없는 CLI 도구용 보조 설치 관리자 (관리자 권한 불필요)
#   1.   GUI 앱 (Android Studio, Slack, Figma, Claude Desktop, Chrome, 1Password,
#        Tailscale, Orca, Lumide, Zed, Rive, TrafficMonitor) + op + Pretendard 폰트
#   1.5. 윈도우 시스템 설정 — 맥의 1.5 Xcode / 1.6 확장 / 3.3 번역 / 9 앱 권한 자리를 한데 모았다.
#        개발자 모드와 긴 경로는 4단계 Flutter보다 **반드시 먼저** 와야 한다.
#        1.5.1 브라우저 확장(ZenHub — Chrome·Edge)   1.5.2 브라우저 번역 언어(한국어)
#        1.5.3 개발자 모드(심볼릭 링크 허용)          1.5.4 긴 경로 허용
#        1.5.5 빌드를 방해할 수 있는 보안 기능 안내 (-DefenderExclusions 를 붙였을 때만
#              Defender 검사 제외 폴더를 실제로 등록한다)
#   2.   Claude Code CLI (공식 install.ps1)
#   2.5. Claude Figma 보조 플러그인 (MCP 직접 등록은 6.6단계)
#   2.6. 다른 AI 코딩 CLI (codex · agy)
#   2.7. Slack CLI
#   3.   CLI 도구 (git, go, pyenv-win, nvm-windows, gh, jq, awscli, Docker Desktop,
#        direnv, lefthook, JDK 17)
#   3.2. Git 사용자 이메일 (git config --global user.email)
#   3.4. GitHub 인증 자동화 (1Password 팀 공용 토큰 → gh auth login)
#   3.5. cocode-skills 팀 플러그인 (사설 레포 install.sh — Git Bash로 실행)
#   4-a. FVM + 팀 표준 Flutter($TeamFlutterVersion)  (+ 4-a-7 Windows 데스크톱 빌드 도구 — Visual Studio Build Tools)
#   4-b. Dart 글로벌 패키지
#   4-c. Google Cloud CLI
#   4-d. DCM
#   4-e. Android SDK 구성요소 + AVD
#   5.   Python 최신 3.x (pyenv-win)
#   6.   Node.js LTS (nvm-windows)
#   6.5. Claude Code 상태줄
#   6.6. OpenCode CLI + 두 도구의 기본 MCP 10개 직접 등록 (기존 설정 병합)
#   7.   PowerShell 프로필 + PSReadLine (맥의 oh-my-zsh 자리)
#   7.3. Oh My Posh 프롬프트 테마 (맥의 powerlevel10k 자리)
#   7.5. MesloLGS NF 폰트  (+ 7.5-a Windows Terminal 폰트 자동 적용)
#   8.5. 팀 공용 토큰 주입 (1Password → 윈도우 사용자 환경변수 — 8.5-a ~ 8.5-g 일곱 묶음)
#   10.  설치 검증 + 다음 단계 안내
#
# 공통 규칙: 모든 단계 멱등(이미 설치 시 스킵) · 실패해도 ⚠ 후 계속 · 시크릿 미커밋
# 실행 옵션: 옵션 없음=전체 · -EnvOnly=토큰만 · -DartOnly=Dart 패키지만 ·
#            -SystemOnly=윈도우 시스템 설정만 · -Help=사용법
# ============================================================

# ------------------------------------------------------------
# PowerShell 7로 다시 실행
#
#   [왜 필요한가]
#   팀 표준 셸은 PowerShell 7(pwsh)이다. 윈도우에 기본으로 깔린 '윈도우 PowerShell 5.1'은
#   같은 명령이라도 동작이 달라(특히 JSON 처리·문자 인코딩), 5.1에서 끝까지 돌리면
#   나중에 사람이 열 pwsh 창과 다른 결과가 만들어진다.
#   → winget으로 pwsh를 깐 뒤, 같은 인자를 그대로 넘겨 pwsh에서 다시 시작한다.
#
#   메모리 실행(iex)으로 시작한 경우에는 다시 실행할 '파일'이 없으므로, 레포에서
#   임시 폴더로 한 번 내려받아 그 파일을 pwsh로 실행한다.
#   내려받기까지 실패하면 다시 실행을 포기하고 5.1에서 그대로 진행한다(멈추지 않는다).
# ------------------------------------------------------------
if ((-not $NoReExec) -and ($PSVersionTable.PSVersion.Major -lt 6)) {
    Write-Step "사전 단계. PowerShell 7 준비 (팀 표준 셸 — 지금은 윈도우 PowerShell $($PSVersionTable.PSVersion)에서 실행 중)"

    if (-not (Test-Cmd 'pwsh')) {
        if (Test-Cmd 'winget') {
            Write-Info 'PowerShell 7을 설치합니다 (몇 분 걸릴 수 있습니다)'
            try {
                & winget install --id Microsoft.PowerShell --exact --silent `
                    --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
            } catch { }
            # 방금 깐 pwsh를 이 창에서 바로 찾을 수 있도록 표준 설치 경로를 PATH에 넣는다.
            Add-UserPath (Join-Path $env:ProgramFiles 'PowerShell\7')
        } else {
            Write-Info 'winget이 아직 없어 PowerShell 7 설치를 건너뜁니다 (0단계에서 winget을 깐 뒤 다시 실행하면 적용됩니다)'
        }
    }

    if (Test-Cmd 'pwsh') {
        # 지금 받은 옵션을 그대로 물려준다 — 사용자가 -EnvOnly 로 실행했는데
        # 다시 실행하면서 전체 설치로 바뀌는 사고를 막는다.
        $forward = @()
        if ($EnvOnly)    { $forward += '-EnvOnly' }
        if ($DartOnly)   { $forward += '-DartOnly' }
        if ($SystemOnly) { $forward += '-SystemOnly' }
        if ($DefenderExclusions) { $forward += '-DefenderExclusions' }
        if ($EnableHyperV)       { $forward += '-EnableHyperV' }

        $selfPath = ''
        if (-not $Standalone) {
            $selfPath = $PSCommandPath
        } else {
            try {
                $selfPath = Join-Path $env:TEMP 'co-win-setup.ps1'
                Invoke-WebRequest -Uri "$RepoRawBase/win-setup.ps1" -OutFile $selfPath -UseBasicParsing -ErrorAction Stop
                try { Unblock-File -LiteralPath $selfPath -ErrorAction SilentlyContinue } catch { }
            } catch {
                $selfPath = ''
            }
        }

        if ($selfPath -and (Test-Path -LiteralPath $selfPath)) {
            Write-Ok 'PowerShell 7에서 다시 시작합니다 (이 창은 그대로 두세요)'
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $selfPath @forward
            exit $LASTEXITCODE
        }
        Write-Warn '다시 실행할 스크립트 파일을 찾지 못했습니다 → 윈도우 PowerShell 5.1에서 그대로 진행합니다'
    } else {
        Write-Warn 'PowerShell 7을 준비하지 못했습니다 → 윈도우 PowerShell 5.1에서 그대로 진행합니다 (수동 설치: winget install --id Microsoft.PowerShell --exact)'
    }
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' co:code 윈도우 개발환경 세팅 (win-setup.ps1)' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
if ($EnvOnly)    { Write-Info '실행 모드: -EnvOnly — 팀 공용 토큰만 다시 주입합니다' }
if ($DartOnly)   { Write-Info '실행 모드: -DartOnly — Dart 글로벌 패키지만 다시 설치합니다' }
if ($SystemOnly) { Write-Info '실행 모드: -SystemOnly — 윈도우 시스템 설정만 다시 점검합니다' }
if ($RunInstall) { Write-Info '실행 모드: 전체 설치 (0~10단계) — 네트워크 상태에 따라 30분~2시간 걸릴 수 있습니다' }
if ($DefenderExclusions -and -not $RunInstall -and -not $SystemOnly) { Write-Info '실행 모드: -DefenderExclusions — 윈도우 시스템 설정 단계만 실행하며 Defender 검사 제외 폴더를 등록합니다' }
if (Test-Admin)  { Write-Info '관리자 권한으로 실행 중 — 개발자 모드·긴 경로 같은 시스템 설정까지 자동으로 켭니다' }
else             { Write-Info '일반 권한으로 실행 중 — 시스템 설정이 필요한 단계는 방법만 안내하고 넘어갑니다 (나중에 관리자 PowerShell에서 -SystemOnly 로 마저 켤 수 있습니다)' }


# ══════════════════════════════════════════════════════════════
# 0 · 0.5 · 1단계 — 패키지 관리자 부트스트랩 + GUI 앱 (전체 설치일 때만)
# ══════════════════════════════════════════════════════════════
if ($RunInstall) {

# ============================================================
# 0. 패키지 관리자 부트스트랩 (winget)
#
#   [왜 이 단계가 맨 앞인가]
#   맥의 Homebrew처럼, 윈도우도 앱·도구를 자동으로 깔아 주는 "설치 관리자"가 먼저 있어야
#   나머지 단계가 전부 돌아간다. 윈도우는 두 개를 같이 쓴다.
#     · winget — 마이크로소프트 공식 설치 관리자. GUI 앱 대부분을 여기서 설치한다.
#     · Scoop  — 관리자 권한 없이 사용자 폴더에 CLI 도구를 설치한다 (winget에 없는 도구용).
#   둘 다 "이미 있으면 건너뛰고, 없으면 자동 설치하고, 그래도 안 되면 경고만 남기고 계속"이다.
#
#   [winget 설치가 왜 3단 구성인가 — 여기서 제일 많이 실패한다]
#   winget은 일반 프로그램이 아니라 윈도우 스토어 앱(MSIX) 형태라, 상황마다 안 잡히는 이유가 다르다.
#     1순위) 계정 재등록        : 앱은 깔려 있는데 "새 계정에 등록만 안 된" 흔한 경우 — 제일 빠르다
#     2순위) 공식 PowerShell 모듈: Repair-WinGetPackageManager가 필요한 부품까지 알아서 받아 준다
#     3순위) GitHub 릴리스 수동  : 위 둘이 다 막힌 회사 PC용 최후 수단
#   셋 다 실패해도 멈추지 않는다 — 경고와 함께 "스토어에서 앱 설치 관리자 설치" 안내만 남긴다.
# ============================================================
Write-Step "0. 패키지 관리자 준비 (winget)"

# 윈도우 PowerShell 5.1은 기본 통신 규격이 낡아서(TLS 1.0/1.1) PowerShell 갤러리·GitHub
# 다운로드가 아무 설명 없이 실패한다. 먼저 TLS 1.2를 켜 둔다.
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
  Write-Info "TLS 1.2 설정을 바꾸지 못했습니다 (대개 문제 없습니다)"
}

# CPU 종류($CpuArch · $ArchIsArm64)는 공통 헬퍼 구역에서 이미 판정해 두었다 —
# ARM64 노트북에서는 x64 전용 설치본이 아예 없는 앱이 있어 여러 단계가 같은 값을 쓴다.

# 윈도우 빌드 번호 — winget과 "사용자별 폰트 설치"는 둘 다 Windows 10 1809(빌드 17763) 이상이 필요하다.
$OsBuild = 0
try {
  $OsCurrentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
  $OsBuild = [int]$OsCurrentVersion.CurrentBuildNumber
} catch {
  try { $OsBuild = [int][System.Environment]::OSVersion.Version.Build } catch { $OsBuild = 0 }
}
Write-Info "이 PC: $CpuArch · 윈도우 빌드 $OsBuild"
if ($OsBuild -gt 0 -and $OsBuild -lt 17763) {
  Write-Warn "Windows 10 1809(빌드 17763)보다 낮은 버전입니다 → winget을 쓸 수 없습니다 (수동 설치: 윈도우 업데이트로 최신 버전을 받은 뒤 이 스크립트를 다시 실행)"
}

# 스토어 앱(MSIX)을 다루는 Appx 모듈은 원래 '윈도우 파워셸' 전용이라, PowerShell 7에서는
# 호환 모드(-UseWindowsPowerShell)로 불러와야 한다. 이 섹션 여러 곳에서 쓰므로 헬퍼로 둔다.
function Initialize-AppxModule {
  if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) { return $true }
  try {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
      Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
    } else {
      Import-Module Appx -ErrorAction Stop
    }
    return $true
  } catch {
    return $false
  }
}

# winget이 "이름만 있는 껍데기"가 아니라 실제로 실행되는지까지 확인한다.
# (앱 설치 관리자가 없으면 winget.exe 자리에 스토어를 여는 껍데기만 남아 있는 경우가 있다)
function Test-WingetReady {
  if (-not (Test-Cmd 'winget')) { return $false }
  $verOut = ''
  try { $verOut = (& winget --version 2>&1 | Out-String) } catch { return $false }
  if ($verOut -match 'v?\d+\.\d+') { return $true }
  return $false
}

# winget 실행 파일이 있는 폴더를 PATH에 먼저 넣어 둔다 — 설치 직후 같은 창에서도 바로 쓰기 위함.
Add-UserPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')

if (Test-WingetReady) {
  Write-Ok "winget 이미 설치됨"
}

# --- 1순위: 사용자 계정에 다시 등록 (앱은 깔려 있는데 명령만 안 잡히는 경우) ---
if (-not (Test-WingetReady)) {
  Write-Info "winget 명령을 찾지 못했습니다 → ① 이 계정에 '앱 설치 관리자'를 다시 등록해 봅니다"
  if (Initialize-AppxModule) {
    try {
      Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
      Add-UserPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
    } catch {
      Write-Info "재등록으로는 해결되지 않았습니다 → 다음 방법을 시도합니다"
    }
  } else {
    Write-Info "스토어 앱 모듈(Appx)을 불러오지 못했습니다 → 다음 방법을 시도합니다"
  }
}

# --- 2순위: 마이크로소프트 공식 PowerShell 모듈 (필요한 부품까지 알아서 받아 준다) ---
if (-not (Test-WingetReady)) {
  Write-Info "② 마이크로소프트 공식 모듈로 winget을 설치합니다 (몇 분 걸릴 수 있습니다)"
  try {
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
      Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    }
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
      Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser -Repository PSGallery -ErrorAction Stop | Out-Null
    }
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop
    Add-UserPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
  } catch {
    Write-Info "공식 모듈 설치가 실패했습니다 → 마지막 방법을 시도합니다"
  }
}

# --- 3순위: GitHub 공식 릴리스에서 설치 파일을 직접 받아 설치 ---
#   흔히 도는 'VCLibs + UI.Xaml 2.8' 레시피는 최신 winget에서 더 이상 맞지 않는다.
#   버전을 손으로 적지 말고, 릴리스가 제공하는 의존성 묶음(zip)에서 이 PC 아키텍처 폴더를
#   통째로 설치하는 것이 정확하다.
if (-not (Test-WingetReady)) {
  Write-Info "③ GitHub 공식 릴리스에서 설치 파일을 직접 받아 설치합니다"
  try {
    $WingetBootDir = Join-Path $env:TEMP 'cocode-wingetboot'
    New-Item -ItemType Directory -Force -Path $WingetBootDir | Out-Null
    $WingetBundle = Join-Path $WingetBootDir 'winget.msixbundle'
    $WingetDepZip = Join-Path $WingetBootDir 'deps.zip'
    Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $WingetBundle -UseBasicParsing -ErrorAction Stop
    Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip' -OutFile $WingetDepZip -UseBasicParsing -ErrorAction Stop
    $WingetDepDir = Join-Path $WingetBootDir 'deps'
    Expand-Archive -Path $WingetDepZip -DestinationPath $WingetDepDir -Force
    $WingetArchDir = Join-Path $WingetDepDir 'x64'
    if ($ArchIsArm64) { $WingetArchDir = Join-Path $WingetDepDir 'arm64' }
    if (Initialize-AppxModule) {
      Get-ChildItem -Path $WingetArchDir -Filter '*.appx' -ErrorAction SilentlyContinue | ForEach-Object {
        # 이미 같은/더 최신 부품이 깔려 있으면 오류가 나는데, 그건 정상이므로 조용히 넘긴다.
        try { Add-AppxPackage -Path $_.FullName -ErrorAction Stop } catch { }
      }
      Add-AppxPackage -Path $WingetBundle -ErrorAction Stop
      Add-UserPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
      # 이 방식으로 깔면 스토어 자동 업데이트가 붙지 않는다 → 나중에 직접 갱신하도록 알려 준다.
      Write-Info "스토어를 거치지 않고 설치해서 자동 업데이트가 붙지 않습니다 → 가끔 'winget upgrade Microsoft.AppInstaller'를 실행해 주세요"
    }
  } catch {
    Write-Info "직접 설치도 실패했습니다"
  }
}

$WingetReady = Test-WingetReady
if ($WingetReady) {
  $WingetVersion = ''
  try { $WingetVersion = (& winget --version 2>&1 | Select-Object -First 1) } catch { $WingetVersion = '' }
  Write-Ok "winget 준비 완료 ($WingetVersion)"
  # winget은 처음 쓸 때 "패키지 목록 이용약관에 동의하시겠어요?" 를 물어본다.
  # 여기서 한 번 털어 두면 이후 앱 설치가 확인 창에 걸려 멈추지 않는다.
  try {
    & winget source update --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    Write-Ok "winget 이용약관 동의 완료 (이후 설치에서 확인 창이 뜨지 않습니다)"
  } catch {
    Write-Info "패키지 목록 갱신에 실패했지만 설치는 계속합니다"
  }
} else {
  Write-Warn "winget 설치 실패 → 건너뜀 (수동 설치: Microsoft Store에서 '앱 설치 관리자'(App Installer)를 설치한 뒤 이 스크립트를 다시 실행)"
}

# ------------------------------------------------------------
# 0.5. 보조 패키지 관리자 준비 (Scoop)
#
#   winget에 없는 CLI 도구를 관리자 권한 없이 사용자 폴더(~\scoop)에 설치하는 데 쓴다.
#   ⚠ Scoop 공식 설치기는 "관리자 PowerShell"에서 실행하면 거부한다. 관리자로 돌리고 있다면
#     -RunAsAdmin 옵션을 붙여야 해서, 아래에서 실행 권한에 따라 갈라 준다.
# ------------------------------------------------------------
Write-Step "0.5. 보조 패키지 관리자 준비 (Scoop)"

# 설치 직후에도 같은 창에서 바로 쓸 수 있도록 shims 폴더를 PATH에 미리 넣는다.
Add-UserPath (Join-Path $env:USERPROFILE 'scoop\shims')

if (Test-Cmd 'scoop') {
  Write-Ok "Scoop 이미 설치됨"
} else {
  # 윈도우 기본값(Restricted)에서는 설치 스크립트 자체가 차단된다 → 현재 사용자만 완화한다.
  try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
  } catch {
    Write-Info "실행 정책을 바꾸지 못했습니다 (회사 정책일 수 있습니다) → 그대로 설치를 시도합니다"
  }
  # ⚠ 남의 설치 스크립트를 이 세션 안에서 그대로 실행하면(irm ... | iex 나 [scriptblock]::Create + &)
  #   설치기 안의 exit 가 win-setup.ps1 자신을 끝내 버린다 — 익명 scriptblock 은 스크립트 경계를
  #   만들지 않아서, try/catch 로도 막지 못한다. Scoop 공식 설치기는 '이미 설치됨', '실행 정책이
  #   막힘' 같은 흔한 상황에서 exit 를 부르므로 그대로 두면 0.5단계에서 세팅 전체가 멈춘다.
  #   그래서 다른 원격 설치기와 똑같이 '임시 파일로 받아 자식 PowerShell 에서' 실행한다.
  #   자식이 죽어도 이 스크립트는 다음 단계로 계속 진행한다.
  $ScoopTmp = Join-Path $env:TEMP 'co-setup-scoop.ps1'
  $ScoopPrevProgress = $ProgressPreference
  $ScoopDownloaded = $false
  try {
    $ProgressPreference = 'SilentlyContinue'   # 진행률 표시줄이 다운로드를 크게 느리게 만든다
    Invoke-WebRequest -UseBasicParsing -Uri 'https://get.scoop.sh' -OutFile $ScoopTmp -ErrorAction Stop
    # 인터넷에서 받은 파일에 붙는 '차단' 표시를 지운다 (남아 있으면 자식 PowerShell 이 실행을 거부한다)
    Unblock-File -LiteralPath $ScoopTmp -ErrorAction SilentlyContinue
    $ScoopDownloaded = $true
  } catch {
    Write-Warn "Scoop 설치 스크립트를 내려받지 못했습니다 → 건너뜀 (수동 설치: 관리자가 아닌 PowerShell 창에서 irm get.scoop.sh | iex)"
  }
  $ProgressPreference = $ScoopPrevProgress

  if ($ScoopDownloaded) {
    # 윈도우 기본 PowerShell(5.1)로 돌린다 — Scoop 공식 설치기가 가장 잘 검증된 환경이다.
    $ScoopPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $ScoopPs)) { $ScoopPs = 'powershell.exe' }
    try {
      if (Test-Admin) {
        Write-Info "관리자 권한으로 실행 중입니다 → Scoop을 -RunAsAdmin 모드로 설치합니다"
        $ScoopOut = & $ScoopPs -NoProfile -ExecutionPolicy Bypass -File $ScoopTmp -RunAsAdmin 2>&1
      } else {
        $ScoopOut = & $ScoopPs -NoProfile -ExecutionPolicy Bypass -File $ScoopTmp 2>&1
      }
      if ($LASTEXITCODE -ne 0) {
        $ScoopTail = (@($ScoopOut) | Select-Object -Last 3) -join ' / '
        Write-Warn "Scoop 설치기가 비정상 종료했습니다(코드 $LASTEXITCODE) → 건너뜀 — 마지막 메시지: $ScoopTail (수동 설치: 관리자가 아닌 PowerShell 창에서  irm get.scoop.sh | iex)"
      }
    } catch {
      Write-Warn "Scoop 설치 실행 실패 ($($_.Exception.Message)) → 건너뜀 (수동 설치: 관리자가 아닌 PowerShell 창에서 irm get.scoop.sh | iex)"
    } finally {
      Remove-Item -LiteralPath $ScoopTmp -Force -ErrorAction SilentlyContinue
    }
    Add-UserPath (Join-Path $env:USERPROFILE 'scoop\shims')
  }
  if (Test-Cmd 'scoop') {
    Write-Ok "Scoop 설치 완료 ($(Join-Path $env:USERPROFILE 'scoop'))"
  } else {
    # 설치기가 0으로 끝났는데도 명령이 안 잡히는 경우가 있다(다른 위치에 이미 있어 조용히 빠져나감 등).
    # 여기서 알려 주지 않으면 30분~2시간짜리 로그 속에 묻혀 아무도 눈치채지 못한다.
    Write-Warn "Scoop 이 설치되지 않았습니다 → 건너뜀 (winget으로 깔리는 도구는 그대로 진행됩니다 · 수동 설치: 관리자가 아닌 PowerShell 창에서  irm get.scoop.sh | iex)"
  }
}

if (Test-Cmd 'scoop') {
  # 버킷(= 설치 목록 저장소)을 추가하려면 git이 필요하다. 아직 없으면 Scoop으로 먼저 깐다.
  if (-not (Test-Cmd 'git')) {
    Install-Scoop -Package 'git' -Name 'git (Scoop 버킷 갱신에 필요)' -ProbeCmd 'git' | Out-Null
  }
  # extras: GUI/일반 앱, versions: 특정 버전 고정, java: JDK 모음
  foreach ($ScoopBucket in @('extras', 'versions', 'java')) {
    $BucketPattern = '(?m)^\s*' + [regex]::Escape($ScoopBucket) + '\b'
    $BucketList = ''
    try { $BucketList = (& scoop bucket list 2>&1 | Out-String) } catch { $BucketList = '' }
    if ($BucketList -match $BucketPattern) {
      Write-Ok "Scoop 버킷 '$ScoopBucket' 이미 추가됨"
    } else {
      try { & scoop bucket add $ScoopBucket 2>&1 | Out-Null } catch { }
      $BucketRecheck = ''
      try { $BucketRecheck = (& scoop bucket list 2>&1 | Out-String) } catch { $BucketRecheck = '' }
      if ($BucketRecheck -match $BucketPattern) {
        Write-Ok "Scoop 버킷 '$ScoopBucket' 추가 완료"
      } else {
        Write-Warn "Scoop 버킷 '$ScoopBucket' 추가 실패 → 건너뜀 (수동 설치: scoop bucket add $ScoopBucket)"
      }
    }
  }
}

# ============================================================
# 1. GUI 앱 설치
#
#   맥의 `brew install --cask`에 해당하는 단계다. 대부분 winget으로 깔지만, winget/Scoop 어디에도
#   등록돼 있지 않은 세 가지(Lumide · Rive · Pretendard 폰트)는 공식 배포처에서 직접 받아 설치한다.
#
#   [맥과 다른 점 — 미리 알고 있으면 덜 당황한다]
#   · 일부 앱은 "이 앱이 장치를 변경하도록 허용할까요?"(UAC) 창이 반드시 뜬다. 예를 눌러 주면 된다.
#     (Android Studio · Chrome · 1Password · Tailscale · Orca · Zed)
#   · Dia 브라우저와 Stats는 윈도우판이 없어 설치하지 않는다 (아래 안내 참고).
#   · 방금 깐 명령(op 등)은 지금 열려 있는 창의 PATH에는 안 잡힐 수 있어, 스크립트가 직접 보정한다.
# ============================================================
Write-Step "1. GUI 앱 설치 (Android Studio, Slack, Figma, Claude Desktop, Chrome, 1Password, Tailscale, Orca, Lumide, Zed, Rive, TrafficMonitor) + 1Password CLI(op) + Pretendard 폰트"

# UAC 승인을 받을 수 있는 상황인지 먼저 판단한다.
#   · 관리자로 실행 중이면 승인 창 없이 진행된다.
#   · 관리자가 아니어도 사람이 화면 앞에 있으면(대화형) 승인 창을 눌러 주면 되므로 그대로 진행한다.
#   · 관리자도 아니고 사람도 없으면(자동 실행 등) 승인을 받을 방법이 없어 그 앱들만 건너뛴다.
$CanElevate = $true
if (-not (Test-Admin)) {
  if (Test-Interactive) {
    Write-Info "관리자 권한 없이 실행 중입니다 → Android Studio · Chrome · 1Password · Tailscale · Orca · Zed 설치 중 '이 앱이 장치를 변경하도록 허용하시겠어요?' 창이 뜹니다. [예]를 눌러 주세요"
  } else {
    $CanElevate = $false
    Write-Warn "관리자 권한도 없고 승인 창을 누를 사람도 없습니다 → 관리자 승인이 필요한 앱은 건너뜀 (수동 설치: 관리자 PowerShell에서 이 스크립트를 다시 실행)"
  }
}

# 설치할 GUI 앱 목록.
#   Id      : winget 패키지 ID (반드시 -e 로 정확히 고정해야 비슷한 이름의 다른 앱이 잡히지 않는다)
#   Scope   : 'user'면 관리자 권한 없이 내 계정에만 설치. 빈 값이면 패키지가 정한 기본값을 따른다.
#             (지원하지 않는 앱에 user를 강제하면 설치 자체가 실패하므로 앱마다 따로 적어 둔다)
#   X64Only : ARM64 노트북용 설치본이 없는 앱 → ARM64에서는 건너뛴다
#   Elevate : 설치 중 UAC 승인 창이 뜨는 앱
$GuiApps = @(
  @{ Id = 'Google.AndroidStudio';             Name = 'Android Studio';                      Scope = '';     X64Only = $true;  Elevate = $true  },
  @{ Id = 'SlackTechnologies.Slack';          Name = 'Slack';                               Scope = 'user'; X64Only = $false; Elevate = $false },
  @{ Id = 'Figma.Figma';                      Name = 'Figma';                               Scope = 'user'; X64Only = $false; Elevate = $false },
  @{ Id = 'Anthropic.Claude';                 Name = 'Claude Desktop';                      Scope = 'user'; X64Only = $false; Elevate = $false },
  @{ Id = 'Google.Chrome';                    Name = 'Google Chrome';                       Scope = '';     X64Only = $false; Elevate = $true  },
  @{ Id = 'AgileBits.1Password';              Name = '1Password';                           Scope = '';     X64Only = $false; Elevate = $true  },
  @{ Id = 'AgileBits.1Password.CLI';          Name = '1Password CLI (op)';                  Scope = '';     X64Only = $false; Elevate = $false; Probe = 'op' },
  @{ Id = 'Tailscale.Tailscale';              Name = 'Tailscale';                           Scope = '';     X64Only = $false; Elevate = $true  },
  @{ Id = 'StablyAI.Orca';                    Name = 'Orca';                                Scope = '';     X64Only = $true;  Elevate = $true  },
  @{ Id = 'ZedIndustries.Zed';                Name = 'Zed';                                 Scope = '';     X64Only = $false; Elevate = $true  },
  @{ Id = 'zhongyang219.TrafficMonitor.Full'; Name = 'TrafficMonitor (작업표시줄 시스템 모니터)'; Scope = '';     X64Only = $false; Elevate = $false }
)

if (-not $WingetReady) {
  Write-Warn "winget이 준비되지 않아 GUI 앱 자동 설치를 건너뜁니다 → 건너뜀 (수동 설치: Microsoft Store에서 '앱 설치 관리자' 설치 후 이 스크립트를 다시 실행)"
} else {
  foreach ($GuiApp in $GuiApps) {
    if ($GuiApp.X64Only -and $ArchIsArm64) {
      Write-Warn "$($GuiApp.Name)은(는) ARM64 윈도우용 설치본이 없습니다 → 건너뜀 (수동 설치: 제조사 홈페이지에서 직접 내려받아 설치)"
      continue
    }
    if ($GuiApp.Elevate -and (-not $CanElevate)) {
      Write-Warn "$($GuiApp.Name)은(는) 관리자 승인(UAC)이 필요합니다 → 건너뜀 (수동 설치: winget install --id $($GuiApp.Id) -e --source winget --accept-package-agreements --accept-source-agreements)"
      continue
    }
    $InstallArgs = @{ Id = $GuiApp.Id; Name = $GuiApp.Name }
    if ($GuiApp.Scope -ne '') { $InstallArgs['Scope'] = $GuiApp.Scope }
    if ($GuiApp.ContainsKey('Probe')) { $InstallArgs['ProbeCmd'] = $GuiApp.Probe }
    Install-Winget @InstallArgs | Out-Null
  }
}

# 맥에서 설치하던 Dia 브라우저는 윈도우 정식 빌드가 아직 없다 (2026년 8월 기준 비공개 베타).
# 목록에서 조용히 사라지면 "빠뜨린 건가?" 하고 헷갈리므로, 왜 없는지 화면에 남긴다.
Write-Info "Dia 브라우저는 윈도우 정식 빌드가 없어 건너뜁니다 → 함께 설치되는 Google Chrome을 사용해 주세요"
# 맥 메뉴막대 앱 Stats도 윈도우판이 없어, 가장 비슷한 TrafficMonitor를 위에서 대신 설치했다.
Write-Info "맥의 Stats(메뉴막대 시스템 모니터)는 윈도우판이 없어, 같은 역할의 TrafficMonitor를 대신 설치했습니다"

# ------------------------------------------------------------
# 1-a. 1Password CLI(op) 실제 동작 확인
#   op는 winget의 '포터블' 방식으로 깔려서, 바로가기 파일(심링크)이 만들어져야 명령으로 잡힌다.
#   그런데 개발자 모드가 꺼져 있으면 이 바로가기 생성이 조용히 실패하는 사례가 있다.
#   → 실행이 되는지 직접 확인하고, 안 되면 실제 설치 폴더를 PATH에 직접 넣어 되살린다.
#   (뒤 단계에서 팀 공용 토큰을 1Password에서 읽어 오므로 op는 반드시 살아 있어야 한다)
# ------------------------------------------------------------
Add-UserPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
if (Test-Cmd 'op') {
  Write-Ok "1Password CLI(op) 명령 확인 완료"
} else {
  $OpExe = $null
  $OpPackagesDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $OpPackagesDir) {
    $OpExe = Get-ChildItem -Path $OpPackagesDir -Recurse -Filter 'op.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  if ($OpExe) {
    Add-UserPath $OpExe.DirectoryName
    if (Test-Cmd 'op') {
      Write-Ok "1Password CLI(op) 경로를 직접 PATH에 추가해 되살렸습니다"
    } else {
      Write-Warn "1Password CLI(op)를 명령으로 부를 수 없습니다 → 건너뜀 (수동 설치: 설정 > 시스템 > 개발자용 (또는 실행창에 start ms-settings:developers) 에서 '개발자 모드'를 켠 뒤 winget install --id AgileBits.1Password.CLI -e 재실행)"
    }
  } else {
    Write-Warn "1Password CLI(op)가 설치되지 않았습니다 → 건너뜀 (수동 설치: winget install --id AgileBits.1Password.CLI -e --source winget --accept-package-agreements --accept-source-agreements)"
  }
}

# ------------------------------------------------------------
# 1-b. Lumide (에이전트 네이티브 코드 에디터)
#   winget·Scoop 어디에도 등록돼 있지 않고, 윈도우판은 설치 프로그램이 아니라 압축(zip) 형태다.
#   → GitHub 공식 릴리스에서 최신 zip을 받아 내 계정 폴더에 풀고, 시작 메뉴 바로가기를 만들어 준다.
#   관리자 권한이 필요 없다. 자동 업데이트가 없으므로 갱신은 나중에 수동으로 해야 한다.
# ------------------------------------------------------------
# Lumide는 Flutter로 만든 앱이라 Visual C++ 재배포 패키지가 필요할 수 있다.
# (미검증 — 없어도 잘 실행되는 PC가 많고, 실패해도 그냥 넘어간다)
if ($CanElevate) {
  Install-Winget -Id 'Microsoft.VCRedist.2015+.x64' -Name 'Visual C++ 재배포 패키지 (Lumide 실행용)' | Out-Null
}

$LumideDir = Join-Path $env:LOCALAPPDATA 'Programs\Lumide'
$LumideExe = $null
if (Test-Path $LumideDir) {
  $LumideExe = Get-ChildItem -Path $LumideDir -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($LumideExe) {
  Write-Ok "Lumide 이미 설치됨 ($LumideDir)"
} else {
  try {
    $GhHeaders = @{ 'User-Agent' = 'cocode-win-setup' }
    $LumideRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/SoFluffyOS/lumide/releases/latest' -Headers $GhHeaders -UseBasicParsing -ErrorAction Stop
    $LumideAsset = $LumideRelease.assets | Where-Object { $_.name -like 'Lumide-Windows-*.zip' } | Select-Object -First 1
    if (-not $LumideAsset) {
      $LumideAsset = $LumideRelease.assets | Where-Object { $_.name -like '*Windows*.zip' } | Select-Object -First 1
    }
    if ($LumideAsset) {
      $LumideZip = Join-Path $env:TEMP 'Lumide.zip'
      Invoke-WebRequest -Uri $LumideAsset.browser_download_url -OutFile $LumideZip -UseBasicParsing -ErrorAction Stop
      New-Item -ItemType Directory -Force -Path $LumideDir | Out-Null
      Expand-Archive -Path $LumideZip -DestinationPath $LumideDir -Force
      Write-Ok "Lumide 설치 완료 ($LumideDir)"
      # 압축을 푼 것뿐이라 시작 메뉴에 안 나온다 → 바로가기를 직접 만들어 준다.
      $LumideMain = Get-ChildItem -Path $LumideDir -Recurse -Filter 'Lumide*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($LumideMain) {
        try {
          $StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
          New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
          $WScriptShell = New-Object -ComObject WScript.Shell
          $LumideLnk = $WScriptShell.CreateShortcut((Join-Path $StartMenuDir 'Lumide.lnk'))
          $LumideLnk.TargetPath = $LumideMain.FullName
          $LumideLnk.WorkingDirectory = $LumideMain.DirectoryName
          $LumideLnk.Save()
          Write-Info "시작 메뉴에 Lumide 바로가기를 만들었습니다"
        } catch {
          Write-Info "시작 메뉴 바로가기는 만들지 못했습니다 (실행 파일: $($LumideMain.FullName))"
        }
      }
    } else {
      Write-Warn "Lumide 윈도우용 zip을 릴리스에서 찾지 못했습니다 → 건너뜀 (수동 설치: https://github.com/SoFluffyOS/lumide/releases 에서 Lumide-Windows-*.zip 을 받아 압축 해제)"
    }
  } catch {
    Write-Warn "Lumide 설치 실패 → 건너뜀 (수동 설치: https://github.com/SoFluffyOS/lumide/releases 에서 Lumide-Windows-*.zip 을 받아 압축 해제)"
  }
}

# ------------------------------------------------------------
# 1-c. Rive (인터랙티브 애니메이션 디자인 툴)
#   winget에 등록돼 있지 않아 공식 사이트의 스토어 앱 파일(MSIX)을 직접 받아 설치한다.
#   관리자 권한은 필요 없지만, 회사 정책으로 '외부 앱 설치(사이드로드)'가 막혀 있으면 실패한다.
#   그럴 땐 설치 없이 브라우저에서 쓰는 방법을 안내한다.
# ------------------------------------------------------------
$RiveInstalled = $false
if (Initialize-AppxModule) {
  try {
    if (Get-AppxPackage -Name '*Rive*' -ErrorAction SilentlyContinue) { $RiveInstalled = $true }
  } catch { }
}
if ($RiveInstalled) {
  Write-Ok "Rive 이미 설치됨"
} elseif (-not (Initialize-AppxModule)) {
  Write-Warn "스토어 앱 모듈(Appx)을 불러오지 못해 Rive를 설치할 수 없습니다 → 건너뜀 (수동 설치: https://rive.app/downloads · 브라우저 사용: https://editor.rive.app)"
} else {
  try {
    $RiveMsix = Join-Path $env:TEMP 'rive_editor.msix'
    Invoke-WebRequest -Uri 'https://releases.rive.app/windows/latest/rive_editor.msix' -OutFile $RiveMsix -UseBasicParsing -ErrorAction Stop
    Add-AppxPackage -Path $RiveMsix -ErrorAction Stop
    Write-Ok "Rive 설치 완료"
  } catch {
    Write-Warn "Rive 설치 실패 → 건너뜀 (수동 설치: https://rive.app/downloads 에서 내려받기 · 설치가 계속 막히면 브라우저 에디터 https://editor.rive.app 를 쓰세요)"
  }
}

# ------------------------------------------------------------
# 1-d. Pretendard 한글 폰트 9종 (Thin ~ Black)
#   디자인 시안에서 널리 쓰는 한글 폰트다. 로컬에 없으면 Figma 시안이 다른 글꼴로 보인다.
#   winget·Scoop 어디에도 없어서 GitHub 공식 릴리스 zip을 받아 직접 설치한다.
#
#   [윈도우 폰트 설치의 함정 세 가지 — 하나라도 빠지면 폰트가 "있는데 안 보인다"]
#   1) 내 계정에만 설치하면 관리자 권한이 필요 없다. 단, Windows 10 1809 이상에서만 된다.
#   2) 레지스트리에 등록할 때 값은 '파일 이름'이 아니라 '전체 경로'여야 한다.
#   3) 폰트 폴더에 '모든 앱 패키지' 읽기 권한을 주지 않으면 스토어 앱·일부 앱에서만 폰트가 안 보인다.
# ------------------------------------------------------------
$FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$PretendardCount = 0
if (Test-Path $FontDir) {
  # TTF 가 없어 OTF 폴백으로 깔린 PC도 '이미 설치됨'으로 알아보도록 두 확장자를 모두 센다.
  #   (같은 두께가 ttf·otf 로 둘 다 있어도 한 종으로 세도록 파일 이름 기준으로 묶는다.)
  $PretendardCount = @(Get-ChildItem -Path $FontDir -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'Pretendard-*.ttf' -or $_.Name -like 'Pretendard-*.otf' } |
    Group-Object BaseName).Count
}
if ($PretendardCount -ge 9) {
  Write-Ok "Pretendard 폰트 9종 이미 설치됨"
} elseif ($OsBuild -gt 0 -and $OsBuild -lt 17763) {
  Write-Warn "이 윈도우 버전에서는 계정별 폰트 설치가 지원되지 않습니다 → 건너뜀 (수동 설치: https://github.com/orioncactus/pretendard/releases 에서 zip을 받아 ttf 파일을 모두 선택 후 우클릭 > '모든 사용자용으로 설치')"
} else {
  try {
    $GhHeaders = @{ 'User-Agent' = 'cocode-win-setup' }
    $FontRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/orioncactus/pretendard/releases/latest' -Headers $GhHeaders -UseBasicParsing -ErrorAction Stop
    # PretendardJP(일본어판)·subset(부분 폰트)은 팀 표준이 아니므로 걸러 낸다.
    $FontAsset = $FontRelease.assets |
      Where-Object { $_.name -like 'Pretendard-*.zip' -and $_.name -notlike '*subset*' } |
      Select-Object -First 1
    if ($FontAsset) {
      $FontWork = Join-Path $env:TEMP 'cocode-pretendard'
      Remove-Item -Path $FontWork -Recurse -Force -ErrorAction SilentlyContinue
      New-Item -ItemType Directory -Force -Path $FontWork | Out-Null
      $FontZip = Join-Path $FontWork 'Pretendard.zip'
      Invoke-WebRequest -Uri $FontAsset.browser_download_url -OutFile $FontZip -UseBasicParsing -ErrorAction Stop
      $FontExtract = Join-Path $FontWork 'unzipped'
      Expand-Archive -Path $FontZip -DestinationPath $FontExtract -Force
      New-Item -ItemType Directory -Force -Path $FontDir | Out-Null

      # 함정 3) 스토어 앱·일부 앱도 이 폰트를 읽을 수 있도록 읽기 권한을 준다.
      #   S-1-15-2-1 = 모든 앱 패키지, S-1-15-2-2 = 제한된 앱 패키지
      try {
        $FontAcl = Get-Acl -Path $FontDir
        foreach ($AppSid in @('S-1-15-2-1', 'S-1-15-2-2')) {
          $SidObject = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList $AppSid
          $AclRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $SidObject, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
          $FontAcl.SetAccessRule($AclRule)
        }
        Set-Acl -Path $FontDir -AclObject $FontAcl
      } catch {
        Write-Info "폰트 폴더 권한 설정을 건너뜁니다 — 스토어 앱에서만 폰트가 안 보일 수 있습니다"
      }

      # 윈도우에서는 TTF(zip 안의 alternative 폴더)를 쓰는 편이 종류 표기 혼동이 없어 안전하다.
      $FontSuffix = ' (TrueType)'
      $FontFiles = @()
      $AlternativeDir = Get-ChildItem -Path $FontExtract -Recurse -Directory -Filter 'alternative' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($AlternativeDir) {
        $FontFiles = @(Get-ChildItem -Path $AlternativeDir.FullName -Filter 'Pretendard-*.ttf' -ErrorAction SilentlyContinue)
      }
      if ($FontFiles.Count -eq 0) {
        # 압축 구조가 바뀌었을 때를 대비한 폴백 — 같은 이름은 하나만 남긴다.
        $FontFiles = @(Get-ChildItem -Path $FontExtract -Recurse -Filter 'Pretendard-*.ttf' -ErrorAction SilentlyContinue |
          Group-Object BaseName | ForEach-Object { $_.Group[0] })
      }
      if ($FontFiles.Count -eq 0) {
        # TTF가 아예 없으면 OTF로 설치한다. 이때는 레지스트리 표기를 OpenType으로 바꿔야 한다.
        $FontSuffix = ' (OpenType)'
        $FontFiles = @(Get-ChildItem -Path $FontExtract -Recurse -Filter 'Pretendard-*.otf' -ErrorAction SilentlyContinue |
          Group-Object BaseName | ForEach-Object { $_.Group[0] })
      }

      $FontRegKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
      if (-not (Test-Path $FontRegKey)) { New-Item -Path $FontRegKey -Force | Out-Null }

      $FontDone = 0
      foreach ($FontFile in $FontFiles) {
        try {
          $FontDest = Join-Path $FontDir $FontFile.Name
          Copy-Item -LiteralPath $FontFile.FullName -Destination $FontDest -Force
          # 함정 2) 값은 파일 이름이 아니라 전체 경로여야 인식된다.
          New-ItemProperty -Path $FontRegKey -Name ($FontFile.BaseName + $FontSuffix) -Value $FontDest -PropertyType String -Force | Out-Null
          $FontDone = $FontDone + 1
        } catch {
          Write-Info "$($FontFile.Name) 등록 실패 → 이 파일만 건너뜁니다"
        }
      }

      if ($FontDone -ge 9) {
        Write-Ok "Pretendard 폰트 $FontDone 종 설치 완료 (Thin·ExtraLight·Light·Regular·Medium·SemiBold·Bold·ExtraBold·Black)"
        Write-Info "이미 열려 있는 앱에는 바로 반영되지 않습니다 — 해당 앱을 껐다 켜 주세요"
      } elseif ($FontDone -gt 0) {
        Write-Warn "Pretendard 폰트가 $FontDone 종만 설치됐습니다 (9종 필요) → 건너뜀 (수동 설치: https://github.com/orioncactus/pretendard/releases 에서 zip을 받아 ttf 전체 선택 후 우클릭 > 설치)"
      } else {
        Write-Warn "Pretendard 폰트 파일을 찾지 못했습니다 → 건너뜀 (수동 설치: https://github.com/orioncactus/pretendard/releases 에서 zip을 받아 ttf 전체 선택 후 우클릭 > 설치)"
      }
    } else {
      Write-Warn "Pretendard 릴리스에서 폰트 zip을 찾지 못했습니다 → 건너뜀 (수동 설치: https://github.com/orioncactus/pretendard/releases)"
    }
  } catch {
    Write-Warn "Pretendard 폰트 설치 실패 → 건너뜀 (수동 설치: https://github.com/orioncactus/pretendard/releases 에서 zip을 받아 ttf 전체 선택 후 우클릭 > 설치)"
  }
}

}



# ══════════════════════════════════════════════════════════════
# 1.5단계 — 윈도우 시스템 설정 · 브라우저 확장 · 번역 (-SystemOnly · -DefenderExclusions 로도 실행)
# ══════════════════════════════════════════════════════════════
if ($RunInstall -or $SystemOnly -or $DefenderExclusions) {

# ============================================================
# 1.5. Windows 시스템 설정 · 브라우저 확장 · 브라우저 번역 (맥 9단계 자리)
#    (macOS 9단계 '전체 디스크 접근 권한'을 Windows 현실에 맞게 대체하고,
#     macOS 1.6단계 '브라우저 확장 자동 등록' · 3.3단계 '번역 언어 자동 설정'을 이식)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   맥 스크립트(mac-setup.sh)의 9단계는 "Orca에 전체 디스크 접근 권한을 켜 주세요"를
#   안내하는 단계였다. 그런데 그 권한은 macOS에만 있는 개념(TCC)이라 Windows에는
#   대응하는 설정 자체가 없다 — Windows의 일반 데스크톱 앱은 별도 승인 없이 사용자
#   파일을 읽는다. 즉 점검할 상태도, 열어줄 설정 창도 없다.
#   그래서 이 단계는 "Windows에서 실제로 사람을 막는 것들"로 내용을 바꿔 넣었다.
#     · 개발자 모드    — 꺼져 있으면 Flutter 앱 빌드가 아예 실패한다 (심볼릭 링크 필요)
#     · 긴 경로 허용   — Flutter/Gradle 캐시 경로가 260자를 넘어 나는 빌드 실패를 줄인다
#     · 보안 팝업 안내 — 방화벽·랜섬웨어 방지 때문에 생기는 '원인 모를 실패'를 미리 알려준다
#   여기에 맥의 1.6단계(ZenHub 확장 자동 등록)와 3.3단계(번역 언어 한국어 설정)를
#   Windows 방식으로 옮겨 함께 처리한다. Windows에는 Dia 브라우저가 아직 없으므로
#   (2026-08 기준 비공개 베타) Chrome과 Edge 두 개만 다룬다.
#
#   [왜 중간에 관리자 권한을 묻나]
#   확장 등록 · 개발자 모드 · 긴 경로는 전부 '컴퓨터 전체 설정(HKLM 레지스트리)'이라
#   관리자 권한이 필요하다. 권한이 없어도 스크립트는 절대 멈추지 않는다 — 경고와
#   '직접 하는 방법'만 남기고 다음으로 넘어간다.
# ============================================================

# ------------------------------------------------------------
# 1.5. 배너 + 이 단계 공통 준비 — 권한 상태 판정 + 레지스트리 경로 분기 (1.5.1~1.5.5 앞에 한 번만 돈다)
#   [32비트/64비트 함정] 64비트 Windows에서 브라우저 확장 등록 경로는
#   HKLM:\SOFTWARE\Wow6432Node\... 이다. 그런데 32비트 PowerShell로 스크립트를 돌리면
#   HKLM:\SOFTWARE\... 를 써도 Windows가 알아서 Wow6432Node로 돌려버려(레지스트리
#   리디렉션) 같은 곳을 두 번 건드린 것처럼 보인다. 그래서 OS 비트수로 경로를 직접
#   갈라 쓰고, 32비트 PowerShell로 실행 중이면 경고를 남긴다.
# ------------------------------------------------------------
Write-Step "1.5. Windows 시스템 설정 · 브라우저 확장 · 번역 (macOS 9단계 대체)"

$IsAdminNow = Test-Admin
if ($IsAdminNow) {
  Write-Ok "관리자 권한으로 실행 중 — 시스템 설정까지 자동으로 적용합니다"
} else {
  Write-Info "지금은 일반 권한으로 실행 중입니다 — 컴퓨터 전체 설정이 필요한 항목은 안내만 남깁니다"
  Write-Info "  (나중에 '관리자 권한으로 실행'한 PowerShell에서 이 스크립트를 다시 돌리면 자동 적용됩니다)"
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
  Write-Warn "32비트 PowerShell로 실행 중입니다 → 레지스트리 경로가 자동으로 바뀔 수 있습니다 (수동 대안: 64비트 PowerShell(C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe 또는 pwsh)에서 다시 실행)"
}

# 브라우저 확장 등록용 레지스트리 루트 (구글·마이크로소프트 공식 문서 기준 경로)
if ([Environment]::Is64BitOperatingSystem) {
  $ChromeExtRoot = 'HKLM:\SOFTWARE\Wow6432Node\Google\Chrome\Extensions'
  $EdgeExtRoot   = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Edge\Extensions'
} else {
  $ChromeExtRoot = 'HKLM:\SOFTWARE\Google\Chrome\Extensions'
  $EdgeExtRoot   = 'HKLM:\SOFTWARE\Microsoft\Edge\Extensions'
}

# ------------------------------------------------------------
# 1.5.1. 브라우저 확장 프로그램 자동 등록 (ZenHub for GitHub) — macOS 1.6단계 이식
#   맥에서는 /Library/Application Support/<브라우저>/External Extensions/<ID>.json 파일을
#   심어두는 '드롭인' 방식을 썼다. Windows는 같은 기능이 파일이 아니라 레지스트리로
#   제공된다(구글 공식 문서 "External Extensions"). 확장 ID 이름의 키를 만들고
#   update_url 값에 크롬 웹스토어 주소를 넣어두면, 다음 브라우저 실행 때 알아서 받아온다.
#
#   [사용자가 통제권을 갖는다 — 이게 중요하다]
#   이 방식으로 등록된 확장은 곧바로 켜지지 않는다. Chrome 25부터는 '사용 안 함' 상태로
#   설치되고 메뉴에 배지가 떠서, 사용자가 확인 창에서 '사용'을 눌러야 켜진다. 사용자가
#   지우면 다시 깔리지도 않는다. '강제 설치(ExtensionInstallForcelist)' 정책을 쓰면
#   확인 창 없이 깔 수 있지만, 대신 사용자가 끄지도 지우지도 못하고 브라우저 설정 곳곳에
#   "조직에서 관리하는 브라우저" 배지가 붙는다 → 개인 노트북에 그 표시를 남기는 건
#   팀 세팅의 성격에 맞지 않아 일부러 쓰지 않는다.
#
#   [Edge는 한 가지가 더 필요하다]
#   ZenHub는 Edge 애드온 스토어에 없고 크롬 웹스토어에만 있다. 그래서 Edge에도 크롬
#   웹스토어 주소(clients2.google.com)를 update_url로 넣어야 하고, Edge의
#   '다른 스토어의 확장 허용' 토글이 켜져 있어야 실제로 설치된다. 그 토글의 기본값을
#   미리 켜주는 '권장(Recommended) 정책'을 함께 넣는다 — 권장 정책이라 사용자가
#   언제든 끌 수 있고 강제성이 없다.
# ------------------------------------------------------------
Write-Step "1.5.1. 브라우저 확장 프로그램 자동 등록 (ZenHub for GitHub — Chrome·Edge)"

$ZenHubExtId    = 'ogcgkffhplmphkaahpmffcafajaocjbd'                        # ZenHub for GitHub (크롬 웹스토어 ID)
$ChromeStoreCrx = 'https://clients2.google.com/service/update2/crx'          # 크롬 웹스토어 배포 주소 (Edge도 이 주소를 써야 한다)
$ZenHubStoreUrl = "https://chromewebstore.google.com/detail/zenhub-for-github/$ZenHubExtId"

# 브라우저가 깔려 있는지 확인한다 (실행 파일이 있는 대표 위치 몇 군데만 본다).
function Test-CocodeBrowserInstalled {
  param([string[]]$Paths)
  foreach ($p in $Paths) {
    if ($p) {
      if (Test-Path -LiteralPath $p) { return $true }
    }
  }
  return $false
}

# 확장 하나를 '외부 확장' 레지스트리에 등록한다. 멱등: 이미 같은 값이면 아무것도 안 한다.
function Register-CocodeExternalExtension {
  param(
    [string]$BrowserName,   # 사람이 읽는 이름 (예: Chrome)
    [string]$ExtRoot,       # 확장 루트 키 (위 9.0에서 비트수에 맞춰 고른 경로)
    [string]$ExtId,         # 확장 ID
    [string]$UpdateUrl,     # 배포 주소
    [bool]$BrowserPresent   # 브라우저 설치 여부
  )

  if (-not $BrowserPresent) {
    Write-Info "$BrowserName 미설치 → 확장 등록 건너뜀"
    return
  }

  $key = Join-Path $ExtRoot $ExtId

  # 멱등 확인 — 읽기는 관리자 권한 없이도 된다.
  try {
    $cur = (Get-ItemProperty -Path $key -Name 'update_url' -ErrorAction SilentlyContinue).update_url
    if ($cur -eq $UpdateUrl) {
      Write-Ok "$BrowserName : ZenHub for GitHub 확장 이미 등록됨"
      return
    }
  } catch {
    # 읽기 실패는 '아직 없음'과 같게 취급하고 아래에서 등록을 시도한다.
    Write-Info "$BrowserName : 기존 등록 상태를 읽지 못했습니다 — 새로 등록을 시도합니다"
  }

  if (-not $IsAdminNow) {
    Write-Warn "$BrowserName : 확장 등록에 관리자 권한이 필요합니다 → 건너뜀 (수동 설치: $ZenHubStoreUrl 에서 '$($BrowserName)에 추가')"
    return
  }

  try {
    New-Item -Path $key -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $key -Name 'update_url' -Value $UpdateUrl -PropertyType String -Force -ErrorAction Stop | Out-Null
    Write-Ok "$BrowserName : ZenHub for GitHub 확장 등록 완료"
    Write-Info "  다음 $BrowserName 실행 때 자동으로 내려받습니다. 처음에는 '사용 안 함' 상태라"
    Write-Info "  브라우저 오른쪽 위 퍼즐/점 3개 메뉴에 뜨는 확인 창에서 '확장 사용'을 한 번 눌러 주세요"
  } catch {
    Write-Warn "$BrowserName : 확장 등록 실패 ($($_.Exception.Message)) → 건너뜀 (수동 설치: $ZenHubStoreUrl)"
  }
}

# Chrome 설치 위치 후보
$ChromeExePaths = @()
if ($env:ProgramFiles)          { $ChromeExePaths += (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe') }
if (${env:ProgramFiles(x86)})   { $ChromeExePaths += (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe') }
if ($env:LOCALAPPDATA)          { $ChromeExePaths += (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe') }

# Edge 설치 위치 후보 (Edge는 Windows에 기본 탑재라 보통 항상 있다)
$EdgeExePaths = @()
if (${env:ProgramFiles(x86)})   { $EdgeExePaths += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe') }
if ($env:ProgramFiles)          { $EdgeExePaths += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }

$ChromePresent = Test-CocodeBrowserInstalled -Paths $ChromeExePaths
$EdgePresent   = Test-CocodeBrowserInstalled -Paths $EdgeExePaths

Register-CocodeExternalExtension -BrowserName 'Chrome' -ExtRoot $ChromeExtRoot -ExtId $ZenHubExtId -UpdateUrl $ChromeStoreCrx -BrowserPresent $ChromePresent
Register-CocodeExternalExtension -BrowserName 'Edge'   -ExtRoot $EdgeExtRoot   -ExtId $ZenHubExtId -UpdateUrl $ChromeStoreCrx -BrowserPresent $EdgePresent

# Edge 전용 — '다른 스토어의 확장 허용' 토글 기본값을 미리 켜 둔다.
#   ⚠ 경로 끝의 \Recommended 가 핵심이다. 이 정책은 '권장' 전용이라 일반(강제) 경로에
#     넣으면 아무 효과가 없다. Edge 101 이상에서 동작한다.
if ($EdgePresent) {
  $edgeRecommendedKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended'
  $edgeOtherStoresName = 'ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled'
  $edgeOtherStoresCur  = (Get-ItemProperty -Path $edgeRecommendedKey -Name $edgeOtherStoresName -ErrorAction SilentlyContinue).$edgeOtherStoresName
  if ($edgeOtherStoresCur -eq 1) {
    Write-Ok "Edge : '다른 스토어의 확장 허용' 기본값 이미 켜짐"
  } elseif (-not $IsAdminNow) {
    Write-Warn "Edge : '다른 스토어의 확장 허용' 설정에 관리자 권한이 필요합니다 → 건너뜀 (수동: edge://extensions 에서 '다른 스토어의 확장 허용' 토글 켜기)"
  } else {
    try {
      New-Item -Path $edgeRecommendedKey -Force -ErrorAction Stop | Out-Null
      New-ItemProperty -Path $edgeRecommendedKey -Name $edgeOtherStoresName -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
      Write-Ok "Edge : '다른 스토어의 확장 허용' 기본값 켜짐 (ZenHub는 크롬 웹스토어에만 있어서 필요합니다)"
      Write-Info "  권장 설정이라 언제든 edge://extensions 에서 다시 끌 수 있습니다"
    } catch {
      Write-Warn "Edge : '다른 스토어의 확장 허용' 설정 실패 ($($_.Exception.Message)) → 건너뜀 (수동: edge://extensions 에서 토글 켜기)"
    }
  }
}

# ------------------------------------------------------------
# 1.5.2. 브라우저 번역 언어 자동 설정 (Chrome·Edge → 한국어) — macOS 3.3단계 이식
#   chrome://settings/languages (Edge는 edge://settings/languages)에서 매번
#   "이 언어로 번역: 한국어" + "번역 안 함: 영어"를 손으로 누르는 번거로움을 없앤다.
#   크로미움 계열 브라우저는 이 값을 프로필 폴더의 Preferences(JSON) 파일에 저장한다
#   (translate.enabled · translate_recent_target · translate_blocked_languages).
#   맥에서는 jq로 고쳤지만 Windows에는 jq가 없으므로 PowerShell 내장 JSON 기능을 쓴다.
#
#   [Windows에서 달라지는 점]
#   맥의 ~/Library/Application Support/Google/Chrome/Default/... 에 해당하는 경로가
#   Windows에서는 %LOCALAPPDATA%\Google\Chrome\User Data\Default\... 다 (중간에
#   'User Data' 폴더가 하나 더 있다).
#
#   [브라우저를 완전히 꺼야 하는 이유]
#   브라우저가 켜져 있으면 종료할 때 자기가 기억하던 설정으로 이 파일을 덮어써서
#   방금 심어둔 값이 사라진다. 그래서 실행 중이면 건드리지 않고 경고만 남긴다.
#
#   [안전장치 3가지 — 이거 없이 고치면 프로필이 깨진다]
#     1) 쓰기 전 .cocode.bak 백업
#     2) ConvertTo-Json -Depth 100 : 기본값(2)으로 저장하면 깊게 중첩된 설정이
#        '@{...}' 같은 글자로 뭉개져 프로필이 통째로 손상된다 (경고도 안 뜬다)
#     3) BOM 없는 UTF-8로 저장 : BOM이 붙으면 크롬이 파일을 못 읽고 프로필을 초기화한다
# ------------------------------------------------------------
Write-Step "1.5.2. 브라우저 번역 언어 자동 설정 (Chrome·Edge → 한국어로 번역, 영어는 번역 안 함)"

function Set-CocodeBrowserTranslateKo {
  param(
    [string]$BrowserName,   # 사람이 읽는 이름
    [string]$ProcessName,   # 실행 중인지 확인할 프로세스 이름 (.exe 없이)
    [string]$UserDataDir,   # 프로필들이 들어있는 상위 폴더 (…\User Data)
    [string]$SettingsUrl    # 실패했을 때 안내할 설정 페이지 주소
  )

  # 브라우저 자체가 없으면(예: Chrome 미설치) 아무것도 하지 않는다.
  $localState = Join-Path $UserDataDir 'Local State'
  $prefs      = Join-Path $UserDataDir 'Default\Preferences'

  # 실행 중이면 건너뛴다 — 종료 시 덮어쓰기 때문에 지금 고쳐봐야 소용이 없다.
  $running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
  if ($running) {
    Write-Warn "$BrowserName 실행 중 → 번역 언어 설정 건너뜀 (완전히 종료한 뒤 이 스크립트를 다시 실행하세요)"
    Write-Info "  창을 다 닫아도 '백그라운드 앱 계속 실행' 설정이나 트레이(시계 옆) 아이콘 때문에"
    Write-Info "  프로세스가 남아 있을 수 있습니다 → 트레이 아이콘에서 '종료' 또는 작업 관리자에서 $ProcessName 종료"
    return
  }

  # 프로필이 여러 개면 Default 프로필에만 적용된다는 점을 알려준다 (맥 스크립트와 동일한 범위).
  if (Test-Path -LiteralPath $localState) {
    try {
      $ls = Get-Content -LiteralPath $localState -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($ls -and $ls.profile -and $ls.profile.info_cache) {
        $profileNames = @($ls.profile.info_cache.PSObject.Properties.Name)
        if ($profileNames.Count -gt 1) {
          Write-Info "$BrowserName 프로필이 $($profileNames.Count)개 있습니다 → 기본 프로필(Default)에만 적용합니다"
          Write-Info "  다른 프로필은 $SettingsUrl 에서 직접 '한국어로 번역 / 영어는 번역 안 함'을 설정해 주세요"
        }
      }
    } catch {
      Write-Info "$BrowserName 프로필 목록을 읽지 못했습니다 — 기본 프로필(Default)만 처리합니다"
    }
  }

  $backup = $prefs + '.cocode.bak'

  try {
    # 아직 한 번도 실행하지 않은 새 PC라면 프로필 폴더 자체가 없다 → 미리 만들어 심어둔다.
    $defaultDir = Split-Path -Parent $prefs
    if (-not (Test-Path -LiteralPath $defaultDir)) {
      New-Item -Path $defaultDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    if (-not (Test-Path -LiteralPath $prefs)) {
      [System.IO.File]::WriteAllText($prefs, '{}', (New-Object System.Text.UTF8Encoding($false)))
    } elseif (-not (Test-Path -LiteralPath $backup)) {
      # 안전장치 1) 되돌릴 수 있게 '사람이 쓰던 원본'을 처음 한 번만 백업한다.
      #   두 번째 실행에서 또 덮어쓰면 백업이 '이미 우리가 고쳐 놓은 파일'이 돼, 아래에서 안내하는
      #   '백업을 원래 이름으로 되돌리기'를 해도 원래 설정으로 돌아가지 못한다.
      Copy-Item -LiteralPath $prefs -Destination $backup -Force -ErrorAction Stop
    }

    $raw = Get-Content -LiteralPath $prefs -Raw -Encoding UTF8
    if (-not $raw) { $raw = '{}' }
    $json = $raw | ConvertFrom-Json
    if ($null -eq $json) { $json = New-Object psobject }

    # 멱등) 이미 '한국어로 번역 + 영어는 번역 안 함'으로 돼 있으면 파일을 건드리지 않고 끝낸다.
    #   매 실행마다 수 MB짜리 Preferences 를 통째로 다시 쓰면, 사람이 직접 바꿔 둔 브라우저 설정이
    #   JSON 을 다시 쓰는 과정에서 흔들릴 수 있다.
    $AlreadyKo = ($json.translate_recent_target -eq 'ko')
    $AlreadyEn = $false
    if ($json.PSObject.Properties.Name -contains 'translate_blocked_languages') {
      $AlreadyEn = (@($json.translate_blocked_languages) -contains 'en')
    }
    if ($AlreadyKo -and $AlreadyEn) {
      Write-Ok "$BrowserName 번역 언어 이미 설정됨 (한국어로 번역, 영어는 번역 안 함)"
      return
    }

    # translate.enabled = true  (번역 기능 자체를 켠다)
    $translateNode = $null
    if ($json.PSObject.Properties.Name -contains 'translate') { $translateNode = $json.translate }
    if ($null -eq $translateNode) { $translateNode = New-Object psobject }
    $translateNode | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $true -Force
    $json | Add-Member -NotePropertyName 'translate' -NotePropertyValue $translateNode -Force

    # translate_recent_target = "ko"  (번역 결과 언어를 한국어로)
    $json | Add-Member -NotePropertyName 'translate_recent_target' -NotePropertyValue 'ko' -Force

    # translate_blocked_languages 에 "en" 추가  (영어 페이지는 번역 제안을 띄우지 않는다)
    $blocked = @()
    if ($json.PSObject.Properties.Name -contains 'translate_blocked_languages') {
      if ($null -ne $json.translate_blocked_languages) { $blocked = @($json.translate_blocked_languages) }
    }
    $blocked = @(@($blocked + 'en') | Select-Object -Unique)
    $json | Add-Member -NotePropertyName 'translate_blocked_languages' -NotePropertyValue ([string[]]$blocked) -Force

    # 안전장치 2) -Depth 100 · 안전장치 3) BOM 없는 UTF-8
    $out = $json | ConvertTo-Json -Depth 100 -Compress
    if (-not $out) {
      Write-Warn "$BrowserName 번역 설정 파일을 만들지 못했습니다 → 건너뜀 (수동 설정: $SettingsUrl)"
      return
    }
    [System.IO.File]::WriteAllText($prefs, $out, (New-Object System.Text.UTF8Encoding($false)))

    # 정말 들어갔는지 다시 읽어 확인한다.
    $check = (Get-Content -LiteralPath $prefs -Raw -Encoding UTF8 | ConvertFrom-Json).translate_recent_target
    if ($check -eq 'ko') {
      Write-Ok "$BrowserName 번역 언어 설정 완료 (한국어로 번역, 영어는 번역 안 함)"
    } else {
      Write-Warn "$BrowserName 번역 설정이 저장되지 않았습니다 → 건너뜀 (수동 설정: $SettingsUrl)"
    }
  } catch {
    Write-Warn "$BrowserName 번역 언어 설정 실패 ($($_.Exception.Message)) → 건너뜀 (수동 설정: $SettingsUrl 에서 '이 언어로 번역: 한국어', '번역 안 함: 영어')"
    Write-Info "  되돌리려면 백업 파일을 원래 이름으로 복사하세요: $backup"
  }
}

if ($ChromePresent) {
  Set-CocodeBrowserTranslateKo -BrowserName 'Chrome' -ProcessName 'chrome' -UserDataDir (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') -SettingsUrl 'chrome://settings/languages'
} else {
  Write-Info "Chrome 미설치 → 번역 언어 설정 건너뜀"
}

if ($EdgePresent) {
  Set-CocodeBrowserTranslateKo -BrowserName 'Edge' -ProcessName 'msedge' -UserDataDir (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') -SettingsUrl 'edge://settings/languages'
} else {
  Write-Info "Edge 미설치 → 번역 언어 설정 건너뜀"
}

# ------------------------------------------------------------
# 1.5.3. 개발자 모드 켜기 (Flutter 앱 빌드에 반드시 필요)
#   [왜 필요한가 — 비개발자용 설명]
#   Flutter는 앱을 만들 때 '심볼릭 링크'라는 바로가기 파일을 만든다. 그런데 Windows는
#   보안상 관리자가 아닌 계정이 이걸 만드는 걸 기본으로 막아 둔다. 그래서 개발자 모드가
#   꺼져 있으면 빌드가 이런 메시지로 실패한다:
#     "Building with plugins requires symlink support.
#      Please enable Developer Mode in your system settings."
#   즉 이건 '있으면 좋은 옵션'이 아니라 없으면 개발을 시작할 수 없는 필수 설정이다.
#
#   [macOS 9단계와 같은 모양]
#   맥에서 전체 디스크 접근 권한 창을 열어주고 사람이 토글을 누르게 했던 것처럼,
#   여기서도 자동 적용을 먼저 시도하고 안 되면 Windows 설정 창을 대신 열어 안내한다.
# ------------------------------------------------------------
Write-Step "1.5.3. 개발자 모드 확인 (Flutter 빌드에 필요한 심볼릭 링크 허용)"

$DevModeKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$DevModeName = 'AllowDevelopmentWithoutDevLicense'

function Test-CocodeDevMode {
  $v = (Get-ItemProperty -Path $DevModeKey -Name $DevModeName -ErrorAction SilentlyContinue).$DevModeName
  return ($v -eq 1)
}

if (Test-CocodeDevMode) {
  Write-Ok "개발자 모드 이미 켜짐 → 건너뜀"
} else {
  $devModeDone = $false

  if ($IsAdminNow) {
    try {
      # 깨끗하게 설치된 Windows에는 이 키 자체가 없을 수 있어 -Force로 먼저 만든다.
      New-Item -Path $DevModeKey -Force -ErrorAction Stop | Out-Null
      New-ItemProperty -Path $DevModeKey -Name $DevModeName -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
      if (Test-CocodeDevMode) {
        $devModeDone = $true
        Write-Ok "개발자 모드 켜짐"
        Write-Info "  바로 적용되지 않으면 로그아웃 후 다시 로그인하면 확실히 반영됩니다"
      }
    } catch {
      Write-Info "개발자 모드를 자동으로 켜지 못했습니다 ($($_.Exception.Message)) — 설정 창으로 안내합니다"
    }
  }

  # 회사에서 관리하는 PC(Intune·그룹 정책)라면 방금 쓴 값이 조용히 되돌아갈 수 있다.
  # 그래서 자동 적용이 안 됐으면 사람에게 넘긴다 — 설정 창을 열어주고 켤 때까지 기다린다.
  if (-not $devModeDone) {
    if (Test-Interactive) {
      try {
        Start-Process 'ms-settings:developers' -ErrorAction Stop
        Write-Info "Windows 설정의 '개발자용' 창을 열었습니다"
      } catch {
        Write-Info "설정 창을 자동으로 열지 못했습니다 → 직접 여세요: 설정 > 시스템 > 개발자용"
      }
      Write-Info "⏸  '개발자 모드' 토글을 켜 주세요."
      Write-Info "   [무엇을 하는 건가요?] Flutter가 앱을 만들 때 쓰는 '바로가기 파일(심볼릭 링크)' 생성을 허용합니다."
      Write-Info "   [켜는 방법] 방금 열린 창에서 맨 위 '개발자 모드' 토글을 켜고, 확인 창이 뜨면 '예'를 누릅니다."
      Write-Info "   ※ 이 설정을 켜지 않으면 Flutter 앱 빌드가 실패합니다 (없으면 개발 시작 자체가 안 됩니다)."
      while ($true) {
        $devAns = Read-Host "   켜셨으면 Enter(다시 확인) · 나중에 하려면 s 입력 후 Enter"
        if ($devAns -eq 's' -or $devAns -eq 'S') {
          Write-Warn "개발자 모드 설정 건너뜀 → 나중에 'start ms-settings:developers' 로 직접 켜 주세요 (안 켜면 Flutter 빌드가 실패합니다)"
          break
        }
        if (Test-CocodeDevMode) {
          Write-Ok "개발자 모드 확인됨"
          break
        }
        Write-Info "아직 꺼져 있는 것으로 보입니다 — 토글이 켜졌는지 확인 후 다시 Enter를 눌러 주세요"
        Write-Info "  (회사에서 관리하는 PC라면 정책으로 잠겨 있을 수 있습니다 → 이럴 땐 s 로 넘기고 IT 담당자에게 문의)"
      }
    } else {
      Write-Warn "비대화형 실행이라 여기서 멈추지 않습니다 → 건너뜀 (수동: 관리자 PowerShell에서 New-ItemProperty -Path '$DevModeKey' -Name $DevModeName -Value 1 -PropertyType DWord -Force · 또는 start ms-settings:developers)"
    }
  }
}

# ------------------------------------------------------------
# 1.5.4. 긴 경로(Long Paths) 허용 + Git 긴 경로 지원
#   [왜 필요한가 — 비개발자용 설명]
#   Windows는 오래전부터 파일 경로 길이를 260자로 제한해 왔다. 그런데 Flutter·Gradle은
#   캐시와 중간 결과물을 아주 깊은 폴더에 만들어서 이 한계를 쉽게 넘고, 그러면
#   "File name too long" 같은 메시지로 빌드나 git clone이 실패한다. 이 제한을 푸는
#   스위치를 미리 켜 둔다.
#
#   ⚠ 켰다고 다 해결되는 건 아니다: 프로그램이 스스로 '긴 경로를 쓰겠다'고 선언해야
#     효과가 있어서, Java(Gradle) 같은 일부 도구는 여전히 260자에 걸린다. 그래서
#     "레포는 C:\src 처럼 짧은 폴더에 두세요" 안내를 함께 남긴다. 적용에는 재부팅이 필요하다.
# ------------------------------------------------------------
Write-Step "1.5.4. 긴 경로(Long Paths) 허용 — Flutter·Gradle 빌드 경로 길이 제한 풀기"

$LongPathKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$LongPathName = 'LongPathsEnabled'
$longPathCur  = (Get-ItemProperty -Path $LongPathKey -Name $LongPathName -ErrorAction SilentlyContinue).$LongPathName

if ($longPathCur -eq 1) {
  Write-Ok "긴 경로 허용 이미 켜짐 → 건너뜀"
} elseif (-not $IsAdminNow) {
  Write-Warn "긴 경로 허용에 관리자 권한이 필요합니다 → 건너뜀 (수동: 관리자 PowerShell에서 New-ItemProperty -Path '$LongPathKey' -Name $LongPathName -Value 1 -PropertyType DWord -Force)"
} else {
  try {
    New-ItemProperty -Path $LongPathKey -Name $LongPathName -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Ok "긴 경로 허용 켜짐 (재부팅 후 적용됩니다)"
  } catch {
    Write-Warn "긴 경로 허용 설정 실패 ($($_.Exception.Message)) → 건너뜀 (수동: 관리자 PowerShell에서 New-ItemProperty -Path '$LongPathKey' -Name $LongPathName -Value 1 -PropertyType DWord -Force)"
  }
}

Write-Info "이 설정만으로 모든 '경로가 너무 김' 오류가 사라지지는 않습니다 (Gradle/Java 등은 여전히 걸릴 수 있음)"
Write-Info "  → 소스 레포는 C:\src\<프로젝트> 처럼 짧은 경로에 두는 것을 권장합니다"

# Git에도 같은 스위치가 따로 있다. 컴퓨터 전체(--system)에 걸면 좋지만 관리자 권한이
# 필요하므로, 실패하면 내 계정 범위(--global)로 넘어간다 — 효과는 사실상 같다.
if (Test-Cmd 'git') {
  # 이미 켜져 있는지 먼저 본다 (읽기는 권한이 필요 없다). 값이 없으면 git이 종료코드 1을
  # 돌려주지만 오류는 아니므로 조용히 넘긴다.
  $gitLongSystem = ''
  $gitLongGlobal = ''
  try {
    $gitLongSystem = (& git config --system --get core.longpaths 2>$null)
    $gitLongGlobal = (& git config --global --get core.longpaths 2>$null)
  } catch {
    Write-Info "Git 설정을 읽지 못했습니다 — 그대로 설정을 시도합니다"
  }
  if ($gitLongSystem -eq 'true' -or $gitLongGlobal -eq 'true') {
    Write-Ok "Git 긴 경로 지원(core.longpaths) 이미 켜짐 → 건너뜀"
  } else {
    $gitLongDone = $false
    if ($IsAdminNow) {
      try {
        & git config --system core.longpaths true 2>$null
        if ($LASTEXITCODE -eq 0) {
          $gitLongDone = $true
          Write-Ok "Git 긴 경로 지원 켜짐 (컴퓨터 전체 · core.longpaths)"
        }
      } catch {
        Write-Info "Git 전체 설정에 쓰지 못했습니다 — 내 계정 설정으로 대신합니다"
      }
    }
    if (-not $gitLongDone) {
      try {
        & git config --global core.longpaths true 2>$null
        if ($LASTEXITCODE -eq 0) {
          Write-Ok "Git 긴 경로 지원 켜짐 (내 계정 · core.longpaths)"
        } else {
          Write-Warn "Git 긴 경로 지원 설정 실패 → 건너뜀 (수동: git config --global core.longpaths true)"
        }
      } catch {
        Write-Warn "Git 긴 경로 지원 설정 실패 ($($_.Exception.Message)) → 건너뜀 (수동: git config --global core.longpaths true)"
      }
    }
  }
} else {
  Write-Info "git 미설치 → Git 긴 경로 설정 건너뜀 (git 설치 후 이 스크립트를 다시 실행하면 적용됩니다)"
}

# ------------------------------------------------------------
# 1.5.5. 빌드를 방해하는 Windows 보안 기능 안내 (설정을 바꾸지 않고 '알려만' 준다)
#   [왜 자동으로 안 바꾸나]
#   여기 나오는 것들은 전부 보안 기능이다. 스크립트가 팀원 PC의 보안을 임의로 낮추는 건
#   맞지 않아서, "이런 팝업이 뜨면 이렇게 하세요"만 알려준다. 미리 알고 있으면
#   '원인 모를 빌드 실패'로 몇 시간 헤매는 일을 막을 수 있다.
# ------------------------------------------------------------
Write-Step "1.5.5. 빌드를 방해할 수 있는 Windows 보안 기능 안내 (설정은 바꾸지 않습니다)"

Write-Info "① Windows Defender 방화벽 팝업"
Write-Info "   Flutter 앱을 처음 실행하거나 안드로이드 기기를 연결할 때 '이 앱의 네트워크 액세스를"
Write-Info "   허용하시겠습니까?' 창이 한 번 뜹니다. 여기서 '취소'를 누르면 기기 연결과 핫 리로드가"
Write-Info "   조용히 실패합니다 → '개인 네트워크'만 체크하고 '액세스 허용'을 눌러 주세요."

Write-Info "② 랜섬웨어 방지(제어된 폴더 액세스)"
Write-Info "   켜져 있으면 빌드 결과물을 폴더에 쓰지 못해 원인 모를 실패가 납니다."
Write-Info "   증상이 보이면: Windows 보안 > 바이러스 및 위협 방지 > 랜섬웨어 방지 에서 상태를 확인하세요."

Write-Info "③ 빌드가 너무 느리다면 — 실시간 검사 영향"
Write-Info "   Flutter/Gradle 캐시는 파일이 수십만 개라 실시간 검사 영향이 큽니다."
Write-Info "   가장 안전한 해법은 Windows 11의 'Dev Drive'(개발자용 드라이브)를 만들어 캐시를 옮기는 것입니다"
Write-Info "   → 만든 뒤: setx PUB_CACHE D:\.pub-cache · setx GRADLE_USER_HOME D:\.gradle"

# 검사 예외(Defender 제외 폴더)는 보안을 실제로 낮추는 설정이라 기본으로 켜지 않는다.
#   pub·Gradle 캐시야말로 외부에서 받아온 코드가 그대로 떨어지는 곳이라, 그 폴더를
#   검사에서 빼는 건 위험이 정확히 겹친다. 원하는 사람만 $DefenderExclusions = $true 를
#   지정했을 때만 적용한다 (스크립트 실행 전 지정하거나 -DefenderExclusions 옵션으로 전달).
$defenderOptIn = $false
$defenderVar = Get-Variable -Name 'DefenderExclusions' -ErrorAction SilentlyContinue
if ($null -ne $defenderVar -and $defenderVar.Value) { $defenderOptIn = $true }

if (-not $defenderOptIn) {
  Write-Info "④ Defender 검사 제외 폴더는 기본으로 설정하지 않습니다 (보안을 실제로 낮추는 설정이라 팀 표준에서 제외)"
  Write-Info "   꼭 필요하면 보안 담당자와 상의 후 -DefenderExclusions 옵션을 붙여 실행하세요."
} elseif (-not $IsAdminNow) {
  Write-Warn "Defender 검사 제외 설정에 관리자 권한이 필요합니다 → 건너뜀 (관리자 PowerShell에서 다시 실행)"
} else {
  try {
    $exclusions = @()
    if ($env:LOCALAPPDATA) { $exclusions += (Join-Path $env:LOCALAPPDATA 'Pub\Cache') }
    if ($env:USERPROFILE)  { $exclusions += (Join-Path $env:USERPROFILE '.gradle') }
    if ($env:LOCALAPPDATA) { $exclusions += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    if ($exclusions.Count -eq 0) {
      Write-Warn "제외할 폴더 경로를 만들지 못했습니다 → 건너뜀"
    } else {
      Add-MpPreference -ExclusionPath $exclusions -ErrorAction Stop
      Write-Ok "Defender 검사 제외 폴더 등록됨 (pub 캐시 · Gradle · Android SDK)"
      Write-Info "  되돌리려면: Remove-MpPreference -ExclusionPath <폴더>"
    }
  } catch {
    Write-Warn "Defender 검사 제외 설정 실패 ($($_.Exception.Message)) → 건너뜀 (변조 방지(Tamper Protection)가 켜져 있거나 회사 관리 PC일 수 있습니다)"
  }
}

}



# ══════════════════════════════════════════════════════════════
# 2 ~ 4-a단계 — AI CLI · MCP · CLI 도구 · Git 이메일 · GitHub 인증 · Flutter/FVM
# ══════════════════════════════════════════════════════════════
if ($RunInstall) {

# ============================================================
# 2. Claude Code CLI (공식 install.ps1)
#
# 왜 이걸 하나요?
#   Claude Code는 터미널에서 쓰는 팀 표준 AI 코딩 도구입니다. 맥에서는 공식 설치
#   스크립트(install.sh)를 curl로 받아 실행했는데, 윈도우에는 같은 역할을 하는 공식
#   install.ps1이 따로 있습니다. WSL(리눅스 흉내 환경) 없이 윈도우에서 바로 돌아가고,
#   설치 위치도 맥의 ~/.local/bin/claude 와 같은 구조인
#   %USERPROFILE%\.local\bin\claude.exe 입니다. 관리자 권한이 필요 없습니다.
#
# 왜 winget이 아니라 공식 스크립트인가요?
#   winget(Anthropic.ClaudeCode)으로도 깔리지만 자동 업데이트가 없고, claude를 켜 둔
#   상태에서는 파일 잠금 때문에 업그레이드가 실패합니다. 팀 표준은 맥과 같은 '알아서
#   최신' 동작이라 공식 스크립트를 1순위, winget을 폴백(2순위)으로 씁니다.
#
# 맥과 다른 점 — 미리 알아두면 당황하지 않습니다
#   1) 방금 깐 도구가 "없다"고 나올 수 있습니다. 윈도우는 이미 열려 있는 터미널의
#      PATH를 갱신하지 않기 때문입니다 → 아래 Update-CoSessionPath로 매번 다시 읽습니다.
#   2) 성공 판정은 '설치 프로그램의 종료 코드'가 아니라 '실행 파일이 실제로 잡히는지'로
#      합니다(맥 스크립트와 같은 방식). 설치는 됐는데 종료 코드만 이상한 경우가 잦습니다.
#   3) 네이티브 윈도우 Claude Code는 샌드박스 기능을 지원하지 않습니다(맥과 다름).
#   4) git·node는 여기서 깔지 않습니다 — 3단계(CLI 도구)가 팀 표준 옵션까지 맞춰
#      설치하므로 여기서 먼저 깔면 그 설정이 적용되지 않습니다. 이 구간에서 git이 없어
#      못 한 일(figma 플러그인)은 3.5단계에서 자동으로 다시 시도합니다.
# ============================================================

# 지역 헬퍼 ①: winget·설치 스크립트가 바꾼 PATH를 지금 이 창에 반영한다.
#   기존 세션 PATH를 지우지 않고 '빠진 항목만' 덧붙인다(다른 섹션이 세션에만 넣어 둔
#   경로를 날리지 않기 위함).
function Update-CoSessionPath {
  try {
    $current = @()
    if (-not [string]::IsNullOrWhiteSpace($env:PATH)) {
      foreach ($p in $env:PATH.Split(';')) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { $current += $p.TrimEnd('\') }
      }
    }
    foreach ($scope in @('Machine', 'User')) {
      $stored = [Environment]::GetEnvironmentVariable('Path', $scope)
      if ([string]::IsNullOrWhiteSpace($stored)) { continue }
      foreach ($p in $stored.Split(';')) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $trimmed = $p.TrimEnd('\')
        if ($current -notcontains $trimmed) { $current += $trimmed }
      }
    }
    if ($current.Count -gt 0) { $env:PATH = ($current -join ';') }
  } catch {
    # PATH 재조합 실패는 치명적이지 않다 — 새 터미널을 열면 저절로 해결된다.
  }
}

# 지역 헬퍼 ②: Git for Windows의 bash.exe 위치를 찾는다(못 찾으면 $null).
#   이 구간의 4가지가 여기에 기댄다 — Claude Code의 Bash 툴 · 플러그인 마켓플레이스(git
#   clone) · gh repo clone · cocode-skills install.sh 실행.
function Get-CoGitBashPath {
  $candidates = @()
  try {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd -and $gitCmd.Source) {
      # ...\Git\cmd\git.exe → ...\Git\bin\bash.exe
      $gitRoot = Split-Path (Split-Path $gitCmd.Source -Parent) -Parent
      if ($gitRoot) { $candidates += (Join-Path $gitRoot 'bin\bash.exe') }
    }
    if ($env:ProgramFiles) { $candidates += "$env:ProgramFiles\Git\bin\bash.exe" }
    if ($env:ProgramW6432) { $candidates += "$env:ProgramW6432\Git\bin\bash.exe" }
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) { $candidates += "$pf86\Git\bin\bash.exe" }
    if ($env:LOCALAPPDATA) { $candidates += "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe" }
  } catch {
    # 경로 조합 중 오류가 나도 그냥 '못 찾음'으로 처리한다 (스크립트를 멈추지 않는다)
  }
  foreach ($c in $candidates) {
    if ($c) {
      try { if (Test-Path $c) { return $c } } catch { }
    }
  }
  return $null
}

# 지역 헬퍼 ③: Claude Code가 쓸 bash.exe 경로를 사용자 환경변수로 못 박는다.
#   지정하지 않으면 Bash 툴이 PowerShell로 떨어지는데, 팀 스킬·훅이 sh 문법을 쓰므로
#   경로를 명시해 두는 편이 안전하다. git이 아직 없으면 조용히 넘어가고 3.5단계에서 재시도.
function Set-CoClaudeGitBash {
  $bashPath = Get-CoGitBashPath
  if (-not $bashPath) { return }
  $already = $null
  try { $already = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User') } catch { }
  if ($already -eq $bashPath) { return }
  try {
    Set-UserEnv 'CLAUDE_CODE_GIT_BASH_PATH' $bashPath
    Write-Ok "Claude Code의 Bash 경로 지정 완료 ($bashPath)"
  } catch {
    Write-Warn "CLAUDE_CODE_GIT_BASH_PATH 설정 실패 → 건너뜀 (수동: 시스템 환경변수에 직접 추가)"
  }
}

# 지역 헬퍼 ④: 원격 PowerShell 설치 스크립트를 '임시 파일로 받아 자식 프로세스에서' 실행.
#   왜 `irm ... | iex` 를 그대로 쓰지 않나 — iex는 남의 코드를 이 스크립트 세션 안에서
#   그대로 실행하는 방식이라, 설치 스크립트가 exit를 부르면 win-setup.ps1 전체가 같이
#   끝나 버린다(중간에 멈추지 않는다는 원칙 위반). 파일로 받아 자식 PowerShell에 넘기면
#   자식이 죽어도 이 스크립트는 계속 진행한다.
function Invoke-CoRemoteInstaller {
  param(
    [string]$Url,                 # 설치 스크립트 주소
    [string]$Slug,                # 임시 파일 이름에 쓸 짧은 영문 이름 (예: claude)
    [string]$ArgLine = '',        # 설치 스크립트에 넘길 인자 문자열 (없으면 인자 없이 실행)
    [switch]$PreferPwsh           # PowerShell 7에서 돌려야 하는 스크립트(예: Slack CLI)
  )
  $tmp = Join-Path $env:TEMP ("co-setup-$Slug.ps1")
  $prevProgress = $ProgressPreference
  try {
    $ProgressPreference = 'SilentlyContinue'   # 진행률 표시줄이 다운로드를 크게 느리게 만든다
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp -TimeoutSec 300
  } catch {
    $ProgressPreference = $prevProgress
    Write-Warn "설치 스크립트를 내려받지 못했습니다: $Url → 건너뜀"
    return $false
  }
  $ProgressPreference = $prevProgress

  # 실행할 PowerShell 고르기 (기본은 윈도우 기본 PowerShell, 필요하면 PowerShell 7)
  $exe = $null
  if ($PreferPwsh) {
    try {
      $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
      if ($pwshCmd -and $pwshCmd.Source) { $exe = $pwshCmd.Source }
    } catch { }
  }
  if (-not $exe) {
    $winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $winPs) { $exe = $winPs } else { $exe = 'powershell.exe' }
  }

  try {
    # -File 대신 -Command 로 부르는 이유: 설치 스크립트에 인자를 넘길 때 $true 같은 값이
    # 문자열로 뭉개지지 않고 그대로 전달된다(Slack CLI의 -SkipGit $true).
    $cmdText = "& '$tmp'"
    if ($ArgLine) { $cmdText = "$cmdText $ArgLine" }
    $out = & $exe -NoProfile -ExecutionPolicy Bypass -Command $cmdText 2>&1
    if ($LASTEXITCODE -ne 0) {
      $tail = ($out | Select-Object -Last 3) -join ' / '
      Write-Info "설치 스크립트가 비정상 종료(코드 $LASTEXITCODE) — 마지막 메시지: $tail"
    }
  } catch {
    Write-Warn "설치 스크립트 실행 실패: $($_.Exception.Message)"
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
  Update-CoSessionPath
  return $true
}

Write-Step "2. Claude Code CLI 설치 (공식 install.ps1)"

# 맥의 `export PATH="$HOME/.local/bin:$PATH"` 와 같은 역할 —
# claude·agy가 여기에 깔리므로, 같은 실행 세션의 뒷단계(2.5 MCP 등록)에서 바로 잡히게 한다.
Add-UserPath (Join-Path $env:USERPROFILE '.local\bin') -Front

if (Test-Cmd 'claude') {
  Write-Ok "claude 이미 설치됨"
} else {
  Invoke-CoRemoteInstaller -Url 'https://claude.ai/install.ps1' -Slug 'claude' | Out-Null
  Add-UserPath (Join-Path $env:USERPROFILE '.local\bin') -Front
  if (-not (Test-Cmd 'claude')) {
    # 폴백: 공식 winget 패키지. 자동 업데이트가 없어 2순위지만, 안 깔리는 것보다는 낫다.
    Write-Info "공식 설치 스크립트로 잡히지 않아 winget으로 다시 시도합니다"
    Install-Winget -Id 'Anthropic.ClaudeCode' -Name 'Claude Code CLI' -ProbeCmd 'claude' | Out-Null
    Update-CoSessionPath
  }
  if (Test-Cmd 'claude') {
    Write-Ok "claude 설치 완료 (%USERPROFILE%\.local\bin\claude.exe · 자동 업데이트 내장)"
  } else {
    Write-Warn "claude 설치 실패 → 건너뜀 (수동 설치: PowerShell에서  irm https://claude.ai/install.ps1 | iex)"
  }
}

# Claude Code가 쓸 Git Bash 경로 지정 (git이 아직 없으면 3.5단계에서 다시 시도)
Set-CoClaudeGitBash
if (-not (Test-Cmd 'git')) {
  Write-Info "Git for Windows는 3단계에서 설치됩니다 — Claude Code의 Bash 툴·플러그인 설치(git clone)는 그때부터 완전해집니다"
}
Write-Info "네이티브 윈도우 Claude Code는 샌드박스 기능을 지원하지 않습니다(맥과 다른 점) — 꼭 필요하면 WSL2에 따로 설치하세요"

# ============================================================
# 2.5. Claude Code Figma 보조 플러그인
#   디자인 작업용 스킬을 설치합니다. 기본 MCP 10개는 6.6단계에서 두 도구에 직접
#   등록하므로 사설 플러그인 설치 여부에 의존하지 않습니다.
#   git이 아직 없으면 3.5단계에서 플러그인 설치를 다시 시도합니다.
# ============================================================

Write-Step "2.5. Claude Code Figma 보조 플러그인 설치 (기본 MCP 등록은 6.6단계)"

$CoFigmaPluginPending = $false   # git이 없어 미뤄 둔 경우 3.5단계에서 다시 시도하려고 표시

if (-not (Test-Cmd 'claude')) {
  Write-Warn "claude CLI가 없어 Figma 보조 플러그인 설치를 건너뜁니다 (2단계 확인 후 재실행)"
} else {
  # --- ① 공식 마켓플레이스 + figma 플러그인 (git 필요) ---
  $pluginList = ''
  if (Test-Cmd 'git') {
    try { & claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | Out-Null } catch { }
    try { $pluginList = (& claude plugin list 2>&1 | Out-String) } catch { $pluginList = '' }
    if ($pluginList -match 'figma@claude-plugins-official') {
      Write-Ok "figma 플러그인 이미 설치됨"
    } else {
      try {
        & claude plugin install 'figma@claude-plugins-official' --scope user 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
          Write-Ok "figma 플러그인 설치 (최초 1회 /mcp 에서 팀 계정 로그인 필요)"
        } else {
          Write-Warn "figma 플러그인 설치 실패 → 건너뜀 (수동: claude plugin install figma@claude-plugins-official --scope user)"
        }
      } catch {
        Write-Warn "figma 플러그인 설치 실패 → 건너뜀 (수동: claude plugin install figma@claude-plugins-official --scope user)"
      }
    }
  } else {
    $CoFigmaPluginPending = $true
    Write-Warn "git이 아직 없어 figma 플러그인 설치를 미룹니다 → 3.5단계에서 자동 재시도 (마켓플레이스가 git clone을 씁니다)"
  }

  # --- ② 예전 방식 정리 ---
  # jira는 과거 OAuth 플러그인이었으나 토큰 방식으로 바꿨다. 남아 있으면 아래 토큰 등록과
  # 이름이 겹치므로 먼저 지운다(없으면 조용히 넘어감 — 멱등).
  if ($pluginList -match 'atlassian@claude-plugins-official') {
    try {
      & claude plugin uninstall 'atlassian@claude-plugins-official' 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { Write-Info "기존 atlassian OAuth 플러그인 제거 (토큰 방식으로 전환)" }
      else { Write-Warn "기존 atlassian OAuth 플러그인 제거 실패 → 수동 제거 필요(claude plugin uninstall atlassian@claude-plugins-official)" }
    } catch { }
  }
}

# ============================================================
# 2.6. 다른 AI 코딩 CLI (codex, antigravity(agy))
#
# 왜 이걸 하나요?
#   Claude Code와 나란히 터미널에서 쓰는 AI 코딩 도구 두 가지입니다.
#     · codex (OpenAI)          : 최초 실행 시 `codex` 로 ChatGPT 계정 로그인
#     · agy   (Google Antigravity): 은퇴한 Gemini CLI의 공식 후속 도구. 최초 실행 시 Google 로그인
#   맥은 둘 다 Homebrew로 깔았지만 윈도우에는 Homebrew가 없어 각 사의 공식 install.ps1을 씁니다.
#
# ⚠ codex를 winget으로 깔면 실행 파일 이름이 codex.exe 가 아니라
#   codex-x86_64-pc-windows-msvc.exe 로 노출되는 알려진 문제가 있습니다(openai/codex#11283).
#   그래서 공식 스크립트를 1순위로 쓰고, winget은 그래도 안 될 때만 폴백으로 씁니다.
# ============================================================
Write-Step "2.6. 다른 AI 코딩 CLI 설치 (codex, antigravity(agy))"

# --- codex (OpenAI) ---
if (Test-Cmd 'codex') {
  Write-Ok "codex 이미 설치됨"
} else {
  Invoke-CoRemoteInstaller -Url 'https://chatgpt.com/codex/install.ps1' -Slug 'codex' | Out-Null
  if (-not (Test-Cmd 'codex')) {
    Write-Info "공식 설치 스크립트로 잡히지 않아 winget으로 다시 시도합니다 (실행 파일 이름 문제가 있을 수 있음)"
    Install-Winget -Id 'OpenAI.Codex' -Name 'codex (OpenAI)' -ProbeCmd 'codex' | Out-Null
    Update-CoSessionPath
  }
  if (Test-Cmd 'codex') {
    Write-Ok "codex 설치 완료 (최초 실행 시 codex 로 ChatGPT 로그인)"
  } else {
    Write-Warn "codex 설치 실패 → 건너뜀 (수동 설치: irm https://chatgpt.com/codex/install.ps1 | iex)"
  }
}

# --- agy (Google Antigravity CLI) ---
#   설치 위치는 %LOCALAPPDATA%\agy\bin (맥의 ~/.local/bin/agy 에 대응).
#   claude와 같은 이유로 성공 판정은 종료 코드가 아니라 실행 파일 존재로 한다.
$agyBin = Join-Path $env:LOCALAPPDATA 'agy\bin'
Add-UserPath $agyBin
if (Test-Cmd 'agy') {
  Write-Ok "agy(antigravity) 이미 설치됨"
} else {
  Invoke-CoRemoteInstaller -Url 'https://antigravity.google/cli/install.ps1' -Slug 'agy' | Out-Null
  Add-UserPath $agyBin
  $agyExe = Join-Path $agyBin 'agy.exe'
  if ((Test-Cmd 'agy') -or (Test-Path $agyExe)) {
    Write-Ok "agy(antigravity) 설치 완료 ($agyBin · 최초 실행 시 agy 로 Google 로그인)"
  } else {
    Write-Warn "agy 설치 실패 → 건너뜀 (수동 설치: irm https://antigravity.google/cli/install.ps1 | iex)"
  }
}

# ============================================================
# 2.7. Slack CLI (slack)
#
# 왜 이걸 하나요?
#   Slack 앱·워크플로를 직접 만들 때 쓰는 공식 CLI입니다(slack MCP와는 별개 도구입니다).
#   윈도우는 설치 스크립트 주소부터 다릅니다 — install.sh 가 아니라 install-windows.ps1.
#
# ⚠ 이 도구가 이 구간에서 가장 까다롭습니다
#   · PowerShell 7(pwsh)이 필요합니다 → 없으면 winget으로 먼저 깝니다.
#   · 세션의 LanguageMode가 FullLanguage여야 합니다(회사 보안 정책으로 제한돼 있으면 실패).
#   · 실패해도 그냥 넘어갑니다. Slack 앱 개발을 하지 않는 팀원에게는 없어도 되는 도구입니다.
# ============================================================
Write-Step "2.7. Slack CLI 설치 (공식 install-windows.ps1)"

if (Test-Cmd 'slack') {
  Write-Ok "slack CLI 이미 설치됨"
} else {
  # ① PowerShell 7 확보 (설치 스크립트의 요구 조건)
  $pwshOk = $false
  try {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { $pwshOk = $true }
  } catch { $pwshOk = $false }
  if (-not $pwshOk) {
    Write-Info "Slack CLI 설치 스크립트는 PowerShell 7이 필요합니다 → 먼저 설치합니다"
    Install-Winget -Id 'Microsoft.PowerShell' -Name 'PowerShell 7' -ProbeCmd 'pwsh' | Out-Null
    Update-CoSessionPath
    try {
      if (Get-Command pwsh -ErrorAction SilentlyContinue) { $pwshOk = $true }
    } catch { $pwshOk = $false }
  }

  if (-not $pwshOk) {
    Write-Warn "PowerShell 7 준비 실패 → Slack CLI 건너뜀 (수동: winget install -e --id Microsoft.PowerShell 후 재실행)"
  } else {
    # ② 언어 모드 점검 — 제한돼 있으면 실패할 가능성이 높지만, 막지 않고 시도한 뒤 결과로 판단한다.
    $langMode = 'Unknown'
    try { $langMode = $ExecutionContext.SessionState.LanguageMode.ToString() } catch { }
    if ($langMode -ne 'FullLanguage') {
      Write-Warn "PowerShell 언어 모드가 $langMode 입니다(회사 정책) → Slack CLI 설치가 실패할 수 있습니다"
    }
    # ③ 설치. git이 이미 있으면 설치 스크립트가 Git을 또 깔지 않도록 -SkipGit 을 넘긴다.
    $slackArgLine = ''
    if (Test-Cmd 'git') { $slackArgLine = '-SkipGit $true' }
    Invoke-CoRemoteInstaller -Url 'https://downloads.slack-edge.com/slack-cli/install-windows.ps1' `
      -Slug 'slack-cli' -ArgLine $slackArgLine -PreferPwsh | Out-Null
    if (-not (Test-Cmd 'slack')) {
      # 플래그 때문에 실패했을 수 있으니 인자 없이 한 번 더 시도한다.
      Invoke-CoRemoteInstaller -Url 'https://downloads.slack-edge.com/slack-cli/install-windows.ps1' `
        -Slug 'slack-cli' -PreferPwsh | Out-Null
    }
    if (Test-Cmd 'slack') {
      Write-Ok "slack CLI 설치 완료 (최초 사용 시 slack login 으로 워크스페이스 인증)"
    } else {
      Write-Warn "slack CLI 설치 실패 → 건너뜀 (수동: PowerShell 7에서  irm https://downloads.slack-edge.com/slack-cli/install-windows.ps1 | iex)"
      Write-Info "이름이 겹쳐 실패한다면 별칭으로 설치할 수 있습니다: install-windows.ps1 -Alias slackcli"
    }
  }
}

# ============================================================
# 3. CLI 도구 (git · go · pyenv · nvm · gh · jq · awscli · Docker Desktop ·
#              direnv · lefthook · JDK 17)
# ------------------------------------------------------------
# 왜 이걸 하나요?
#   맥 세팅 스크립트(mac-setup.sh)의 3단계 "brew install ..." 목록을 윈도우로 옮긴 부분입니다.
#   팀이 매일 쓰는 명령줄(터미널) 도구를 한 번에 깔아 둡니다. 대부분 winget(윈도우 기본
#   앱 설치 관리자)으로 설치하고, winget에 없는 pyenv 만 공식 스크립트로 설치합니다.
#
# 맥과 다른 점 — 미리 알아두면 당황하지 않습니다
#   1) 방금 깐 도구가 "없다"고 나올 수 있습니다. 윈도우는 설치가 끝나도 '이미 열려 있는'
#      터미널 창의 PATH(명령 검색 경로)를 갱신하지 않기 때문입니다. 그래서 이 스크립트는
#      설치할 때마다 PATH를 다시 읽어 들이고, 그래도 안 잡히면 '새 터미널에서 확인'이라고
#      안내만 하고 넘어갑니다. 실제로는 정상 설치된 경우가 대부분입니다.
#   2) 관리자 권한이 필요한 항목이 있습니다(긴 경로 허용, 개발자 모드, JAVA_HOME 등).
#      관리자로 실행하지 않았다면 그 항목만 건너뛰고 "나중에 무엇을 하면 되는지"를 알려 줍니다.
#      사용자를 막지 않습니다.
#   3) 맥 전용 도구는 빼거나 대체품으로 바꿨습니다.
#      cocoapods·fastlane(Xcode가 있어야 의미가 있음) 제외,
#      colima → Docker Desktop, zsh-syntax-highlighting → PowerShell 내장 PSReadLine,
#      docker-compose → 별도 설치 없이 Docker Desktop 내장("docker compose", 하이픈 없음).
# ============================================================
Write-Step "3. CLI 도구 설치 (git, go, pyenv, nvm, gh, jq, awscli, Docker Desktop, direnv, lefthook, JDK 17)"

# 지역 헬퍼: winget으로 방금 깐 도구는 '이 창'의 PATH에 아직 없다.
#   시스템/사용자 PATH를 다시 읽어 현재 세션 PATH에 없는 항목만 덧붙인다(중복·유실 없음).
function Update-CliToolPath {
  try {
    $current = @()
    if (-not [string]::IsNullOrWhiteSpace($env:PATH)) {
      foreach ($p in $env:PATH.Split(';')) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { $current += $p.TrimEnd('\') }
      }
    }
    foreach ($scope in @('Machine', 'User')) {
      $stored = [Environment]::GetEnvironmentVariable('Path', $scope)
      if ([string]::IsNullOrWhiteSpace($stored)) { continue }
      foreach ($p in $stored.Split(';')) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $trimmed = $p.TrimEnd('\')
        if ($current -notcontains $trimmed) { $current += $trimmed }
      }
    }
    if ($current.Count -gt 0) { $env:PATH = ($current -join ';') }
  } catch {
    # PATH 재조합 실패는 치명적이지 않다 — 새 터미널을 열면 저절로 해결된다.
  }
}

# ------------------------------------------------------------
# 3-1. winget으로 한 번에 설치하는 기본 도구들
#   맥의 FORMULAE 배열과 같은 역할. 하나가 실패해도 나머지는 계속 깐다.
#   ⚠ winget 패키지 ID는 대소문자까지 정확히 맞아야 한다(예: GitHub.cli — CLI 아님).
#   Custom  : 설치 프로그램에 덧붙일 옵션 (winget 기본 무인 설치 스위치는 그대로 유지된다)
#   Elevate : 머신 전체에 깔려 관리자 승인(UAC) 창이 뜨는 도구 — 승인해 줄 사람이 없으면 건너뛴다
# ------------------------------------------------------------
$cliTools = @(
  @{
    Name = 'git'
    Id   = 'Git.Git'
    Probe = 'git'
    # 무인 설치 옵션(Inno Setup)을 그대로 넘겨 Flutter가 요구하는 설정을 처음부터 맞춘다.
    #   EnableSymlinks=Enabled : 심볼릭 링크 체크아웃 허용 (Flutter 플러그인 빌드에 필요)
    #   CRLFOption=CRLFCommitAsIs : 줄바꿈을 건드리지 않음(core.autocrlf=false).
    #     기본값(CRLFAlways)으로 두면 gradlew·.sh 파일이 깨지고 맥 팀원과 diff가 폭발한다.
    #   PathOption=Cmd : git을 일반 터미널(PowerShell/cmd)에서도 쓸 수 있게 PATH에 등록
    # ⚠ Override(통째로 대체)가 아니라 Custom(뒤에 덧붙이기)으로 넘긴다.
    #    Override로 넘기면 winget이 기본으로 넣어 주는 무인 설치 스위치(/VERYSILENT 등)까지
    #    사라져 Git 설치 마법사 창이 뜨고, 사람이 [다음]을 다 누를 때까지 스크립트가 멈춘다.
    Custom = '/o:EnableSymlinks=Enabled /o:CRLFOption=CRLFCommitAsIs /o:PathOption=Cmd /o:SSHOption=OpenSSH /o:BashTerminalOption=MinTTY /o:DefaultBranchOption=main'
    Elevate = $true   # 머신 전체에 설치 → 관리자 승인(UAC) 창이 뜬다
  },
  @{ Name = 'go';      Id = 'GoLang.Go';            Probe = 'go';      Elevate = $true },
  @{ Name = 'gh';      Id = 'GitHub.cli';           Probe = 'gh';      Elevate = $true },
  @{ Name = 'jq';      Id = 'jqlang.jq';            Probe = 'jq' },
  @{ Name = 'awscli';  Id = 'Amazon.AWSCLI';        Probe = 'aws';     Elevate = $true },
  @{ Name = 'direnv';  Id = 'direnv.direnv';        Probe = 'direnv' },
  @{ Name = 'lefthook'; Id = 'evilmartians.lefthook'; Probe = 'lefthook' },
  # ⚠ Microsoft.OpenJDK.17 은 무인 설치 시 JAVA_HOME 을 잡아 주지 않는 알려진 문제가 있어 Temurin 을 쓴다
  #   (4-e 안드로이드 단계도 같은 패키지를 찾으므로, 여기서 깔아 두면 그 단계가 다시 깔지 않는다)
  @{ Name = 'JDK 17 (Temurin)'; Id = 'EclipseAdoptium.Temurin.17.JDK'; Probe = 'java'; Elevate = $true }
)

foreach ($tool in $cliTools) {
  # 머신 전체에 깔리는 도구(Elevate = $true)는 설치 중 관리자 승인(UAC) 창이 뜬다.
  # 관리자도 아니고 그 창을 눌러 줄 사람도 없는 실행이면 창 앞에서 멈추므로 미리 건너뛴다.
  # (이미 깔려 있으면 승인이 필요 없으니 그대로 진행한다)
  $toolNeedsApproval = $false
  if ($tool.ContainsKey('Elevate') -and $tool.Elevate -and (-not $CanElevate)) { $toolNeedsApproval = $true }
  if ($toolNeedsApproval -and $tool.ContainsKey('Probe') -and (Test-Cmd $tool.Probe)) { $toolNeedsApproval = $false }
  if ($toolNeedsApproval) {
    Write-Warn "$($tool.Name) 설치에는 관리자 승인(UAC)이 필요합니다 → 건너뜀 (수동 설치: 관리자 PowerShell에서 winget install -e --id $($tool.Id) --accept-package-agreements --accept-source-agreements)"
    continue
  }
  try {
    $params = @{ Id = $tool.Id; Name = $tool.Name }
    if ($tool.ContainsKey('Probe')) { $params['ProbeCmd'] = $tool.Probe }
    if ($tool.ContainsKey('Override')) { $params['Override'] = $tool.Override }
    if ($tool.ContainsKey('Custom'))   { $params['Custom']   = $tool.Custom }
    $installed = Install-Winget @params
    if (-not $installed) {
      Write-Info "수동 설치: winget install -e --id $($tool.Id) --accept-package-agreements --accept-source-agreements"
    }
  } catch {
    Write-Warn "$($tool.Name) 설치 중 오류 → 건너뜀 (수동 설치: winget install -e --id $($tool.Id))"
  }
  Update-CliToolPath
}

# ------------------------------------------------------------
# 3-1-1. lefthook 사용 안내 (맥과 동일)
#   도구만 깔릴 뿐, 실제로 켜는 건 레포마다 한 번씩이다.
# ------------------------------------------------------------
if (Test-Cmd 'lefthook') {
  Write-Info "lefthook.yml 이 있는 프로젝트 폴더에서 최초 1회 'lefthook install' 실행이 필요합니다"
  Write-Info "훅 명령이 sh 문법(grep·xargs·파이프)을 쓰면 Git for Windows의 bash가 필요합니다 — 위에서 git을 설치했다면 준비된 상태입니다"
}

# ------------------------------------------------------------
# 3-2. Git 후속 설정 (인스톨러 옵션만으로는 부족한 부분)
#   ① core.longpaths: 윈도우 기본 260자 경로 제한 때문에 pub cache·Gradle 캐시에서
#      "파일을 찾을 수 없음"이 납니다. 인스톨러 옵션이 없어 설치 후 따로 켜야 합니다.
#   ② 개발자 모드 + 긴 경로 레지스트리: 심볼릭 링크/긴 경로를 OS 차원에서 허용합니다.
#      둘 다 관리자 권한이 필요하며, 없으면 안내만 남기고 건너뜁니다.
# ------------------------------------------------------------
if (Test-Cmd 'git') {
  # core.longpaths — 관리자면 시스템 전역(--system), 아니면 최소한 내 계정(--global)에라도 건다.
  try {
    $longPathsScope = '--global'
    if (Test-Admin) { $longPathsScope = '--system' }
    $currentLongPaths = ''
    try { $currentLongPaths = (& git config $longPathsScope --get core.longpaths 2>$null) } catch { $currentLongPaths = '' }
    if ("$currentLongPaths".Trim() -eq 'true') {
      Write-Ok "git core.longpaths 이미 켜져 있음 ($longPathsScope)"
    } else {
      & git config $longPathsScope core.longpaths true 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) {
        Write-Ok "git core.longpaths 활성화 ($longPathsScope · 긴 경로 파일 체크아웃 허용)"
      } else {
        Write-Warn "git core.longpaths 설정 실패 → 건너뜀 (수동: 관리자 터미널에서 git config --system core.longpaths true)"
      }
    }
    if (-not (Test-Admin)) {
      Write-Info "관리자 권한이 아니라 내 계정에만 적용했습니다 — 전역 적용은 관리자 터미널에서 'git config --system core.longpaths true'"
    }
  } catch {
    Write-Warn "git core.longpaths 설정 중 오류 → 건너뜀 (수동: git config --system core.longpaths true)"
  }

  # core.autocrlf — 이미 예전에 깔린 git이라 인스톨러 옵션이 안 먹었을 수 있으므로 값으로 한 번 더 맞춘다.
  try {
    $autocrlf = ''
    try { $autocrlf = (& git config --global --get core.autocrlf 2>$null) } catch { $autocrlf = '' }
    if ("$autocrlf".Trim() -eq 'false') {
      Write-Ok "git core.autocrlf=false 이미 설정됨 (줄바꿈 자동 변환 끔)"
    } else {
      & git config --global core.autocrlf false 2>$null | Out-Null
      Write-Ok "git core.autocrlf=false 설정 (맥·CI와 줄바꿈이 어긋나 diff가 폭발하는 걸 막습니다)"
    }
  } catch {
    Write-Warn "git core.autocrlf 설정 실패 → 건너뜀 (수동: git config --global core.autocrlf false)"
  }
}

# 개발자 모드(심볼릭 링크 허용) + NTFS 긴 경로 허용 — 둘 다 관리자 권한 필요
if (Test-Admin) {
  try {
    $devModeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    if (-not (Test-Path $devModeKey)) { New-Item -Path $devModeKey -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $devModeKey -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Ok "윈도우 개발자 모드 활성화 (Flutter가 요구하는 심볼릭 링크 생성 허용 · 재부팅 후 확실히 적용)"
  } catch {
    Write-Warn "개발자 모드 설정 실패 → 건너뜀 (수동: 설정 > 시스템 > 개발자용 > '개발자 모드' 켜기 · 또는 실행창에 start ms-settings:developers)"
  }
  try {
    $fsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    New-ItemProperty -Path $fsKey -Name 'LongPathsEnabled' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Write-Ok "윈도우 긴 경로(260자 제한 해제) 활성화 (pub cache·Gradle 캐시 경로가 길어 필요)"
  } catch {
    Write-Warn '긴 경로 레지스트리 설정 실패 → 건너뜀 (수동: 관리자 터미널에서 reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f)'
  }
} else {
  Write-Warn "관리자 권한이 아니라 '개발자 모드'·'긴 경로 허용'을 건너뜁니다 → 나중에 관리자 PowerShell에서 이 스크립트를 다시 실행하세요"
  Write-Info "이 둘이 꺼져 있으면 Flutter 플러그인 빌드(심볼릭 링크)와 긴 경로 캐시에서 실패할 수 있습니다"
}

# ------------------------------------------------------------
# 3-3. Go 작업 경로(GOPATH\bin) PATH 등록
#   맥 스크립트가 .zshrc에 GOPATH/bin을 넣던 것과 같은 처리.
#   Go 본체 경로는 설치 파일이 알아서 등록하지만, 'go install'로 깐 명령이 들어가는
#   %USERPROFILE%\go\bin 은 아무도 등록해 주지 않아 직접 넣어야 한다.
# ------------------------------------------------------------
try {
  $goBin = Join-Path $env:USERPROFILE 'go\bin'
  if (-not (Test-Path $goBin)) { New-Item -Path $goBin -ItemType Directory -Force -ErrorAction Stop | Out-Null }
  Add-UserPath $goBin
  Write-Ok "Go 도구 경로 등록 ($goBin — 'go install'로 받은 명령을 바로 실행)"
} catch {
  Write-Warn "Go 도구 경로 등록 실패 → 건너뜀 (수동: 사용자 환경변수 Path에 %USERPROFILE%\go\bin 추가)"
}

# ------------------------------------------------------------
# 3-4. JAVA_HOME 지정 (JDK 17 — 안드로이드 빌드용)
#   맥의 openjdk@17에 해당. 설치 파일이 대개 JAVA_HOME을 잡아 주지만, 안 잡힌 경우를 대비해
#   실제 설치 폴더를 찾아 사용자 환경변수로 고정한다(안드로이드 SDK 단계에서 이 값을 쓴다).
# ------------------------------------------------------------
try {
  $javaHome = $env:JAVA_HOME
  if ([string]::IsNullOrWhiteSpace($javaHome)) {
    $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
  }
  if ([string]::IsNullOrWhiteSpace($javaHome)) {
    $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
  }
  $javaHomeValid = $false
  if (-not [string]::IsNullOrWhiteSpace($javaHome)) {
    if (Test-Path (Join-Path $javaHome 'bin\java.exe')) { $javaHomeValid = $true }
  }

  if ($javaHomeValid) {
    Write-Ok "JAVA_HOME 이미 설정됨 ($javaHome)"
  } else {
    # 설치 폴더 후보: Microsoft Build of OpenJDK → Eclipse Temurin 순으로 찾는다.
    $jdkCandidates = @()
    $searchRoots = @(
      @{ Path = (Join-Path $env:ProgramFiles 'Microsoft'); Filter = 'jdk-17*' },
      @{ Path = (Join-Path $env:ProgramFiles 'Eclipse Adoptium'); Filter = 'jdk-17*' }
    )
    foreach ($root in $searchRoots) {
      if (-not (Test-Path $root.Path)) { continue }
      $found = Get-ChildItem -Path $root.Path -Directory -Filter $root.Filter -ErrorAction SilentlyContinue
      foreach ($dir in $found) {
        if (Test-Path (Join-Path $dir.FullName 'bin\java.exe')) { $jdkCandidates += $dir }
      }
    }
    if ($jdkCandidates.Count -gt 0) {
      $picked = ($jdkCandidates | Sort-Object Name -Descending | Select-Object -First 1)
      Set-UserEnv 'JAVA_HOME' $picked.FullName
      Add-UserPath (Join-Path $picked.FullName 'bin')
      Write-Ok "JAVA_HOME 설정 ($($picked.FullName))"
    } else {
      Write-Warn "JDK 17 설치 폴더를 찾지 못했습니다 → JAVA_HOME 설정 건너뜀 (수동 설치: winget install -e --id EclipseAdoptium.Temurin.17.JDK)"
    }
  }
} catch {
  Write-Warn "JAVA_HOME 설정 중 오류 → 건너뜀 (수동: 시스템 환경변수에 JAVA_HOME = JDK 설치 폴더 지정)"
}

# ------------------------------------------------------------
# 3-5. pyenv (윈도우판: pyenv-win) — 여러 파이썬 버전을 골라 쓰는 도구
#   winget에 등록돼 있지 않아 공식 설치 스크립트(install-pyenv-win.ps1) 하나로만 설치한다.
#   scoop 으로 깔면 실체가 %USERPROFILE%\scoop\apps\pyenv 에 들어가, 아래 PYENV_ROOT·PATH
#   보정(%USERPROFILE%\.pyenv 기준)과 어긋나 한 PC에 pyenv 가 두 벌 깔린다 → scoop 경로는 쓰지 않는다.
#   맥과 달리 셸에 'eval "$(pyenv init -)"' 같은 설정을 넣지 않는다.
#   대신 shims 폴더가 PATH 맨 앞에 있으면 끝이다.
# ------------------------------------------------------------
$pyenvRoot = Join-Path $env:USERPROFILE '.pyenv\pyenv-win'
$pyenvBat = Join-Path $pyenvRoot 'bin\pyenv.bat'

if ((Test-Cmd 'pyenv') -or (Test-Path $pyenvBat)) {
  Write-Ok "pyenv 이미 설치됨"
} else {
  $pyenvDone = $false
  # 아래 scoop 경로는 설치 위치(%USERPROFILE%\scoop\apps\pyenv)가 달라 쓰지 않는다.
  # (어떤 코드였는지 알 수 있도록 지우지 않고 주석으로만 남겨 둔다)
  <#
  try {
    if (Test-Cmd 'scoop') {
      $pyenvDone = Install-Scoop -Package 'pyenv' -Name 'pyenv-win' -Bucket 'main' -ProbeCmd 'pyenv'
    }
  } catch {
    $pyenvDone = $false
  }
  #>
  # 공식 설치 스크립트로 설치한다 (설치 위치: %USERPROFILE%\.pyenv)
  if (-not $pyenvDone) {
    try {
      $pyenvInstaller = Join-Path $env:TEMP 'install-pyenv-win.ps1'
      Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1' -OutFile $pyenvInstaller -ErrorAction Stop
      # 회사 정책으로 스크립트 실행이 막혀 있을 수 있어, 이 실행에만 정책을 풀어 준다.
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pyenvInstaller 2>$null | Out-Null
      if (Test-Path $pyenvBat) { $pyenvDone = $true }
    } catch {
      $pyenvDone = $false
    }
  }
  if ($pyenvDone) {
    Write-Ok "pyenv 설치 완료"
  } else {
    Write-Warn "pyenv 설치 실패 → 건너뜀 (수동 설치: https://github.com/pyenv-win/pyenv-win 의 install-pyenv-win.ps1 실행 · ⚠ scoop 판은 설치 위치가 달라 환경변수와 어긋나므로 쓰지 마세요)"
  }
}

# 환경변수·PATH 보정 — 설치 스크립트가 이미 넣었더라도 값이 맞는지 매번 확인한다(멱등).
if (Test-Path $pyenvBat) {
  try {
    $pyenvValue = $pyenvRoot + '\'
    foreach ($name in @('PYENV', 'PYENV_ROOT', 'PYENV_HOME')) {
      Set-UserEnv $name $pyenvValue
    }
    # PATH 앞쪽 순서가 'bin → shims'가 되도록 shims를 먼저, bin을 나중에 맨 앞으로 넣는다.
    Add-UserPath (Join-Path $pyenvRoot 'shims') -Front
    Add-UserPath (Join-Path $pyenvRoot 'bin') -Front
    Write-Ok "pyenv 환경변수·PATH 등록 (PYENV·PYENV_ROOT·PYENV_HOME + bin·shims)"
    Write-Info "파이썬 실제 설치는 뒤쪽 '파이썬' 단계에서 진행합니다 (pyenv install <버전> -q · -q 를 빼면 설치 마법사 창이 뜹니다)"
    Write-Info "python 명령이 Microsoft Store 안내 창으로 튄다면: 설정 > 앱 > 고급 앱 설정 > 앱 실행 별칭에서 python.exe·python3.exe 를 끄세요"
  } catch {
    Write-Warn "pyenv 환경변수 등록 실패 → 건너뜀 (수동: PYENV·PYENV_ROOT·PYENV_HOME 을 $pyenvRoot\ 로 설정하고 bin·shims 를 Path 맨 앞에 추가)"
  }
}

# ------------------------------------------------------------
# 3-6. nvm (윈도우판: nvm-windows) — 여러 Node.js 버전을 골라 쓰는 도구
#   ⚠ 가장 중요한 전제: 이미 Node.js가 깔려 있으면 nvm이 제대로 동작하지 않는다.
#     (nvm은 Node 폴더를 바꿔 끼우는 방식이라 기존 설치와 충돌한다)
#     그래서 기존 Node를 발견하면 설치를 강행하지 않고 안내만 남긴다.
#   맥↔윈도우 명령 대응: nvm install --lts → nvm install lts,
#                        nvm use --lts     → nvm use lts,
#                        nvm alias default → (없음. 윈도우는 nvm use 가 곧 기본값)
# ------------------------------------------------------------
if (Test-Cmd 'nvm') {
  Write-Ok "nvm 이미 설치됨"
  if (-not (Test-Admin)) {
    Write-Info "'nvm use' 는 관리자 권한 터미널에서 실행해야 안정적으로 동작합니다"
  }
} else {
  $existingNode = $null
  try { $existingNode = Get-Command node -ErrorAction SilentlyContinue } catch { $existingNode = $null }
  if ($existingNode) {
    Write-Warn "이미 설치된 Node.js 발견 ($($existingNode.Source)) → nvm 설치 건너뜀 (충돌 방지)"
    Write-Info "제어판 > 프로그램 제거 에서 Node.js 를 지운 뒤 이 스크립트를 다시 실행하면 nvm 이 설치됩니다"
    Write-Info "지우기 어렵다면 대안: winget install -e --id Schniz.fnm (관리자 권한 없이 쓰는 Node 버전 관리자)"
  } else {
    $nvmOk = $false
    try {
      $nvmOk = Install-Winget -Id 'CoreyButler.NVMforWindows' -Name 'nvm-windows' -ProbeCmd 'nvm'
    } catch {
      $nvmOk = $false
    }
    Update-CliToolPath
    if ($nvmOk) {
      Write-Info "Node.js 실제 설치는 뒤쪽 'Node.js' 단계에서 진행합니다 (nvm install lts → nvm use lts)"
      if (-not (Test-Admin)) {
        Write-Warn "'nvm use' 는 관리자 권한이 필요합니다 → Node 설치 단계가 실패하면 관리자 PowerShell에서 다시 실행하세요"
      }
    } else {
      # 대체재: fnm — 관리자 권한 없이 동작하고 맥 nvm의 --lts/기본 버전 개념을 그대로 옮길 수 있다.
      Write-Info "nvm 대신 fnm(관리자 권한 불필요한 Node 버전 관리자) 설치를 시도합니다"
      $fnmOk = $false
      try {
        $fnmOk = Install-Winget -Id 'Schniz.fnm' -Name 'fnm (nvm 대체)' -ProbeCmd 'fnm'
      } catch {
        $fnmOk = $false
      }
      Update-CliToolPath
      if ($fnmOk) {
        Write-Ok "fnm 설치 완료 (fnm install --lts / fnm default <버전> 으로 사용)"
        Write-Info "폴더 이동 시 자동 전환을 쓰려면 PowerShell 프로필에 'fnm env --use-on-cd | Out-String | Invoke-Expression' 한 줄을 추가하세요"
      } else {
        Write-Warn "Node 버전 관리자 설치 실패 → 건너뜀 (수동 설치: winget install -e --id CoreyButler.NVMforWindows 또는 winget install -e --id Schniz.fnm)"
      }
    }
  }
}

# ------------------------------------------------------------
# 3-7. Docker Desktop (맥의 colima + docker + docker-compose 자리)
#   윈도우에는 colima가 없어 Docker Desktop이 사실상 표준입니다.
#   맥처럼 'colima start' 한 줄로 띄울 수 없고 아래 순서를 거쳐야 CLI가 붙습니다:
#     ① WSL2 준비 → ② 설치 → ③ 재부팅 → ④ docker-users 그룹 → ⑤ Docker Desktop 앱 최초 1회 실행
#   그래서 이 단계는 '깔아 두는 것'까지만 하고, 나머지는 완료 안내로 넘깁니다.
#   ⚠ 라이선스: 직원 250명 이상 또는 연매출 1000만 달러 이상 조직은 유료 구독이 필요합니다.
# ------------------------------------------------------------
# ① WSL2 — Docker Desktop이 내부적으로 쓰는 리눅스 실행 환경
$wslReady = $false
try {
  if (Test-Cmd 'wsl') {
    & wsl.exe --status *> $null
    if ($LASTEXITCODE -eq 0) { $wslReady = $true }
  }
} catch {
  $wslReady = $false
}
if ($wslReady) {
  Write-Ok "WSL2 이미 사용 가능 (Docker Desktop의 실행 기반)"
} else {
  if (Test-Admin) {
    try {
      # --no-distribution : 리눅스 배포판까지 받지 않고 'WSL 기능'만 켠다(설치 시간·용량 절약).
      #   구형 윈도우에는 이 옵션이 없어 실패할 수 있는데, 그때는 안내만 남기고 계속 진행한다.
      & wsl.exe --install --no-distribution *> $null
      if ($LASTEXITCODE -eq 0) {
        Write-Ok "WSL2 설치 요청 완료 (재부팅 후 적용됩니다)"
      } else {
        Write-Warn "WSL2 자동 설치 실패 → 건너뜀 (수동: 관리자 PowerShell에서 wsl --install 실행 후 재부팅)"
      }
    } catch {
      Write-Warn "WSL2 자동 설치 실패 → 건너뜀 (수동: 관리자 PowerShell에서 wsl --install 실행 후 재부팅)"
    }
  } else {
    Write-Warn "관리자 권한이 아니라 WSL2 설치를 건너뜁니다 (수동: 관리자 PowerShell에서 wsl --install → 재부팅)"
  }
}

# ② Docker Desktop 설치
#   머신 전체에 깔리므로 설치 중 관리자 승인(UAC) 창이 뜬다.
#   관리자도 아니고 승인 창을 눌러 줄 사람도 없는 실행(자동 실행 등)에서는 창 앞에서 멈추므로 건너뛴다.
$dockerCanInstall = $true
if ((-not $CanElevate) -and (-not (Test-Cmd 'docker'))) {
  $dockerCanInstall = $false
  Write-Warn "Docker Desktop 설치에는 관리자 승인(UAC)이 필요합니다 → 건너뜀 (수동 설치: 관리자 PowerShell에서 winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements)"
}
$dockerOk = $false
try {
  if ($dockerCanInstall) { $dockerOk = Install-Winget -Id 'Docker.DockerDesktop' -Name 'Docker Desktop' -ProbeCmd 'docker' }
} catch {
  $dockerOk = $false
}
Update-CliToolPath
if (-not $dockerOk) {
  Write-Info "수동 설치: winget install -e --id Docker.DockerDesktop (또는 무료 대안 winget install -e --id suse.RancherDesktop)"
}

# ③ docker-users 그룹 — 여기에 속해야 관리자가 아니어도 docker 명령을 쓸 수 있다.
if (Test-Admin) {
  try {
    $dockerGroup = Get-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue
    if ($dockerGroup) {
      $alreadyMember = $false
      $members = Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue
      foreach ($m in $members) {
        if ("$($m.Name)".EndsWith('\' + $env:USERNAME)) { $alreadyMember = $true }
      }
      if ($alreadyMember) {
        Write-Ok "docker-users 그룹에 이미 포함됨"
      } else {
        Add-LocalGroupMember -Group 'docker-users' -Member $env:USERNAME -ErrorAction Stop
        Write-Ok "docker-users 그룹에 현재 사용자 추가 (다시 로그인해야 적용)"
      }
    }
  } catch {
    Write-Warn "docker-users 그룹 추가 실패 → 건너뜀 (수동: 관리자 PowerShell에서 Add-LocalGroupMember -Group docker-users -Member $env:USERNAME)"
  }
}
Write-Info "Docker는 설치만으로 끝나지 않습니다 — 재부팅 후 'Docker Desktop' 앱을 한 번 실행해야 docker 명령이 붙습니다"
Write-Info "맥과 달리 docker-compose(하이픈)가 아니라 'docker compose' (띄어쓰기)로 씁니다 — Docker Desktop에 기본 포함이라 따로 설치하지 않습니다"

# ------------------------------------------------------------
# 3-8. direnv 셸 연결 (폴더별 환경변수 자동 로딩)
#   맥의 .zshrc에 있던 'eval "$(direnv hook zsh)"' 에 해당하는 처리를
#   PowerShell 프로필에 한 줄 넣어 준다. 이미 있으면 건드리지 않는다.
#   ⚠ 반드시 $PROFILE.CurrentUserAllHosts(Profile.ps1)에 넣는다 — 그냥 $PROFILE 은
#     '지금 이 호스트 전용' 파일이라, 여기에 넣으면 VS Code 통합 터미널이나 다른 호스트에서는
#     direnv 가 조용히 동작하지 않는다. 7단계의 팀 공용 설정도 같은 파일을 쓴다.
#   ⚠ PowerShell 7 + direnv 2.37.1 이상에서 동작한다(cmd.exe에는 연결 방법이 없다).
# ------------------------------------------------------------
if (Test-Cmd 'direnv') {
  try {
    $profilePath = $PROFILE.CurrentUserAllHosts
    if ([string]::IsNullOrWhiteSpace($profilePath)) { $profilePath = Join-Path $HOME 'Documents\PowerShell\Profile.ps1' }
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDir)) { New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    # ⚠ 여기서 빈 프로필을 만들어 버리면, 뒤(7단계)에서 '스크립트 옆에 놓아둔 Profile.ps1 을
    #   출발점으로 삼는' 처리가 '이미 파일이 있다'는 이유로 통째로 건너뛰어진다.
    #   그래서 이 단계에서도 같은 씨앗 규칙을 그대로 적용한다.
    if (-not (Test-Path $profilePath)) {
      $direnvSeed = ''
      if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
        $direnvSeedCandidate = Join-Path $ScriptDir 'Profile.ps1'
        if (Test-Path -LiteralPath $direnvSeedCandidate) { $direnvSeed = $direnvSeedCandidate }
      }
      if ($direnvSeed) {
        Copy-Item -LiteralPath $direnvSeed -Destination $profilePath -Force -ErrorAction Stop
        Write-Ok "스크립트 옆의 Profile.ps1 을 프로필 출발점으로 복사했습니다 ($profilePath)"
      } else {
        New-Item -Path $profilePath -ItemType File -Force -ErrorAction Stop | Out-Null
      }
    }
    $profileText = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
    if ("$profileText" -like '*direnv hook pwsh*') {
      Write-Ok "direnv 셸 연결 이미 등록됨 ($profilePath)"
    } else {
      $hookBlock = @'

# [co:code] direnv — 폴더에 .envrc 가 있으면 환경변수를 자동으로 불러옵니다 (win-setup.ps1이 추가)
if (Get-Command direnv -ErrorAction SilentlyContinue) {
  Invoke-Expression "$(direnv hook pwsh)"
}
'@
      Add-Content -Path $profilePath -Value $hookBlock -Encoding UTF8 -ErrorAction Stop
      Write-Ok "direnv 셸 연결 등록 ($profilePath · 새 터미널부터 적용)"
    }
  } catch {
    Write-Warn 'direnv 셸 연결 등록 실패 → 건너뜀 (수동: $PROFILE.CurrentUserAllHosts 파일 안에 Invoke-Expression "$(direnv hook pwsh)" 한 줄 추가)'
  }
}

Update-CliToolPath

# ============================================================
# 3.2. Git 전역 사용자 이메일 설정 (커밋 작성자 정보)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   내가 만든 코드가 누구 작업인지 기록되도록, 커밋에 쓸 회사 이메일을 한 번 등록한다.
#   이미 등록돼 있으면 그대로 두고 건너뛴다(멱등).
#   사람이 보고 있지 않은 실행(자동화·CI)에서는 입력을 기다리지 않고 건너뛴다 —
#   나중에 스크립트를 다시 실행하면 그때 물어본다.
# ============================================================
Write-Step "3.2. Git 사용자 이메일 설정 (git config --global user.email)"

if (-not (Test-Cmd 'git')) {
    Write-Warn "git이 없어 이메일 설정을 건너뜁니다 (앞의 'CLI 도구 설치' 단계에서 git 설치가 실패했습니다 · 수동: winget install -e --id Git.Git 로 설치한 뒤 이 스크립트를 다시 실행하면 그때 물어봅니다)"
} else {
    $gitEmailCurrent = ''
    try { $gitEmailCurrent = ("$(& git config --global user.email 2>$null)").Trim() } catch { $gitEmailCurrent = '' }

    if (-not [string]::IsNullOrWhiteSpace($gitEmailCurrent)) {
        Write-Ok "이미 설정됨 ($gitEmailCurrent)"
    } elseif (Test-Interactive) {
        while ($true) {
            Write-Host "  ✉️  커밋에 사용할 회사 이메일을 입력하세요 (예: cody@cocode.im) · 건너뛰려면 s 입력 후 Enter: " -NoNewline
            $gitEmail = ''
            try { $gitEmail = Read-Host } catch { $gitEmail = 's' }
            if ($null -eq $gitEmail) { $gitEmail = 's' }
            $gitEmail = $gitEmail.Trim()

            if ($gitEmail -ieq 's') {
                Write-Warn "Git 이메일 설정 건너뜀 → 나중에 직접 실행: git config --global user.email <이메일>"
                break
            }
            if ($gitEmail -like '*@*') {
                try {
                    & git config --global user.email $gitEmail 2>&1 | Out-Null
                    Write-Ok "user.email 설정 완료 ($gitEmail)"
                } catch {
                    Write-Warn "user.email 설정 실패 → 건너뜀 (수동: git config --global user.email $gitEmail)"
                }
                break
            }
            Write-Host "  ✗ 이메일 형식이 아닙니다(@가 없음) — 다시 입력해 주세요." -ForegroundColor Red
        }
    } else {
        Write-Warn "비대화형 실행 → Git 이메일 설정 건너뜀. 직접 실행: git config --global user.email <이메일>"
    }
}

# ============================================================
# 3.4. GitHub 인증 자동화 (1Password 팀 공용 토큰 → gh auth login)
#
# 왜 이걸 하나요?
#   coco-de 조직의 skills·co-bricks 레포는 비공개라, 바로 아래 3.5단계(cocode-skills)와
#   4단계의 cob 설치가 GitHub 로그인 없이는 실패합니다. 예전에는 사람이 직접
#   'gh auth login'을 해야 했지만, 여기서 1Password 팀 공용 토큰으로 대신 로그인합니다.
#
# 동작 전제
#   1) op(1Password CLI) 설치 + 팀 계정 연결
#      ⚠ 윈도우는 맥과 연동 방법이 다릅니다 — 1Password 8 앱에서
#        ① 설정 > 보안 에서 'Windows Hello' 를 켠 뒤
#        ② 설정 > 개발자 > '1Password CLI와 통합' 체크
#        (맥은 Touch ID + 개발자 탭이었습니다)
#   2) 1Password 팀 공용 항목: "API Token" 볼트 > "GitHub API Token" > credential 필드
#
# 멱등성: 이미 로그인돼 있으면(수동이든 자동이든) 다시 로그인하지 않고 건너뜁니다.
#
# ⚠ 윈도우에서 반드시 지켜야 하는 것 — 토큰을 파일에 쓰지 않습니다
#   PowerShell은 외부 프로그램에 대한 `< 파일` 입력 리디렉션을 지원하지 않고,
#   토큰을 파일로 저장하면 UTF8 BOM·CRLF가 붙어 값이 깨집니다.
#   그래서 메모리 파이프(`$token | gh auth login --with-token`)만 씁니다.
# ============================================================
Write-Step "3.4. GitHub 인증 자동화 (1Password → gh auth login)"

# gh 인증 상태 확인용 지역 헬퍼 (3.5단계에서도 같은 판정을 쓴다)
function Test-CoGhAuth {
  if (-not (Test-Cmd 'gh')) { return $false }
  try {
    & gh auth status 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

if (-not (Test-Cmd 'gh')) {
  Write-Warn "gh(GitHub CLI)가 없어 GitHub 인증을 건너뜁니다 (앞의 'CLI 도구 설치' 단계에서 gh 설치가 실패했습니다 · 수동: winget install -e --id GitHub.cli 로 설치한 뒤 이 스크립트를 다시 실행)"
} elseif (Test-CoGhAuth) {
  Write-Ok "gh 이미 인증됨 (건너뜀)"
} else {
  $ghToken = $null
  try {
    # Get-OpSecret은 1Password 앱이 잠겨 있거나 통합이 꺼져 있으면 $null을 돌려준다(멈추지 않음).
    $ghToken = Get-OpSecret 'op://API Token/GitHub API Token/credential'
  } catch {
    $ghToken = $null
  }
  if ($ghToken) { $ghToken = $ghToken.Trim() }   # 토큰 뒤에 붙는 줄바꿈 제거

  if ([string]::IsNullOrWhiteSpace($ghToken)) {
    Write-Warn "1Password에서 GitHub 토큰을 읽지 못했습니다 → 건너뜀 (수동: gh auth login)"
    Write-Info "1Password 앱 > 설정 > 보안 에서 'Windows Hello' 를 켠 뒤, 설정 > 개발자 > '1Password CLI와 통합' 을 체크하세요"
    Write-Info "팀 공용 항목이 없다면 'API Token' 볼트에 'GitHub API Token'(credential 필드, 레포 read 권한 PAT) 생성을 팀 관리자에게 요청하세요"
  } else {
    $prevOutputEncoding = $OutputEncoding
    try {
      # BOM 없는 UTF-8로 파이프에 흘려야 토큰 앞에 눈에 안 보이는 문자가 붙지 않는다.
      $OutputEncoding = New-Object Text.UTF8Encoding($false)
      $ghToken | & gh auth login --hostname github.com --with-token 2>&1 | Out-Null
      if (Test-CoGhAuth) {
        try { & gh auth setup-git 2>&1 | Out-Null } catch { }
        Write-Ok "1Password 토큰으로 gh 자동 로그인 완료 (git도 이 인증을 그대로 사용)"
      } else {
        Write-Warn "gh 자동 로그인 실패 → 건너뜀 (수동: gh auth login · 토큰 권한 확인)"
      }
    } catch {
      Write-Warn "gh 자동 로그인 중 오류 → 건너뜀 (수동: gh auth login)"
    } finally {
      $OutputEncoding = $prevOutputEncoding
      $ghToken = $null
      Remove-Variable ghToken -ErrorAction SilentlyContinue   # 토큰 값을 메모리에 남기지 않는다
    }
  }
}

# ============================================================
# 3.5. cocode-skills 팀 플러그인 설치 (사설 레포 coco-de/skills)
#
# 왜 이걸 하나요?
#   marionette·dart·figma(serve)·dev-cycle·coui 등 팀이 만든 cc-* 플러그인 묶음입니다.
#   비공개 레포라 `claude plugin marketplace add`로는 받을 수 없어 팀 install 스크립트로
#   동기화합니다. 전제는 gh 인증(3.4단계) + Git for Windows + jq(3단계) 입니다.
#
# ⚠ 윈도우에서 유일하게 '스크립트로 해결되지 않는' 항목이 여기 있습니다 — rsync
#   팀 install.sh 는 rsync 명령을 씁니다. 그런데 윈도우에는 쓸 만한 rsync 정식 패키지가
#   없고(Git for Windows에도 없음), install.sh 는 rsync가 없으면 스스로 중단합니다.
#   그래서 이 단계는 다음 순서로 시도합니다:
#     ① 레포에 install.ps1(윈도우용)이 있으면 그걸로 설치 — bash·jq·rsync가 전혀 필요 없음
#     ② 없으면 rsync 유무를 확인해, 있으면 Git Bash로 install.sh 실행
#     ③ rsync가 없으면 안내만 남기고 건너뜀 (업스트림에 cp -a 폴백 추가 또는 install.ps1
#        추가가 선행 과제입니다 — README에 그대로 적혀 있습니다)
#
# 그 밖의 윈도우 주의점
#   · install.sh 를 저장할 때 Set-Content/Out-File을 쓰면 BOM·CRLF가 붙어 첫 줄(#!/bin/bash)이
#     깨집니다 → 반드시 바이트 그대로 씁니다.
#   · 회사(도메인) PC에서는 Git Bash의 홈 폴더가 네트워크 드라이브일 수 있어, 스킬이 엉뚱한
#     곳에 깔립니다 → HOME을 %USERPROFILE%로 못 박아 넘깁니다.
# ============================================================
Write-Step "3.5. cocode-skills 팀 플러그인 설치 (coco-de/skills)"

# 2.5단계에서 git이 없어 미뤄 둔 figma 플러그인을 여기서 마저 설치한다(3단계에서 git 설치 완료).
if ($CoFigmaPluginPending -and (Test-Cmd 'claude') -and (Test-Cmd 'git')) {
  try {
    & claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | Out-Null
    & claude plugin install 'figma@claude-plugins-official' --scope user 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "figma 플러그인 설치 (2.5단계에서 미뤄 둔 항목 · 최초 1회 /mcp 로그인 필요)" }
    else { Write-Warn "figma 플러그인 재시도 실패 → 건너뜀 (수동: claude plugin install figma@claude-plugins-official --scope user)" }
  } catch {
    Write-Warn "figma 플러그인 재시도 실패 → 건너뜀 (수동: claude plugin install figma@claude-plugins-official --scope user)"
  }
}
# git이 이제 있으니 Claude Code의 Bash 경로도 여기서 다시 확정한다(이미 맞으면 아무 일도 안 함).
Set-CoClaudeGitBash

if (-not (Test-CoGhAuth)) {
  Write-Warn "gh 인증이 필요합니다 → 3.4단계 안내를 확인하거나 'gh auth login' 실행 후 스크립트를 다시 실행하세요"
} else {
  $gitBash = Get-CoGitBashPath

  # ① 윈도우용 install.ps1이 레포에 있으면 최우선 (bash·jq·rsync 불필요)
  $psInstallerB64 = ''
  try { $psInstallerB64 = ((& gh api repos/coco-de/skills/contents/install.ps1 --jq .content 2>$null) -join '') } catch { $psInstallerB64 = '' }

  if (-not [string]::IsNullOrWhiteSpace($psInstallerB64)) {
    Write-Info "레포에서 윈도우용 install.ps1을 찾았습니다 → 이 경로로 설치합니다"
    $tmpPs1 = Join-Path $env:TEMP 'cocode-skills-install.ps1'
    try {
      [IO.File]::WriteAllBytes($tmpPs1, [Convert]::FromBase64String($psInstallerB64))
      $winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
      if (-not (Test-Path $winPs)) { $winPs = 'powershell.exe' }
      $out = & $winPs -NoProfile -ExecutionPolicy Bypass -File $tmpPs1 2>&1
      if ($LASTEXITCODE -ne 0) { Write-Info "install.ps1 종료 코드 $LASTEXITCODE — 마지막 메시지: $(($out | Select-Object -Last 2) -join ' / ')" }
    } catch {
      Write-Warn "install.ps1 실행 실패: $($_.Exception.Message)"
    } finally {
      Remove-Item $tmpPs1 -Force -ErrorAction SilentlyContinue
    }
  } elseif (-not $gitBash) {
    Write-Warn "Git for Windows의 bash.exe를 찾지 못해 건너뜁니다 (앞의 'CLI 도구 설치' 단계에서 git 설치가 실패했습니다 · 수동: winget install -e --id Git.Git 로 설치한 뒤 이 스크립트를 다시 실행)"
  } elseif (-not (Test-Cmd 'jq')) {
    Write-Warn "jq가 없어 건너뜁니다 (앞의 'CLI 도구 설치' 단계에서 jq 설치가 실패했습니다 · 수동: winget install -e --id jqlang.jq 로 설치한 뒤 이 스크립트를 다시 실행)"
  } else {
    # ② rsync 확인 — install.sh 가 반드시 요구하는 도구
    $hasRsync = $false
    try {
      $probe = (& $gitBash -lc "if command -v rsync >/dev/null 2>&1; then echo yes; fi" 2>$null | Out-String)
      if ($probe -match 'yes') { $hasRsync = $true }
    } catch { $hasRsync = $false }

    if (-not $hasRsync) {
      Write-Warn "rsync가 없어 cocode-skills 설치를 건너뜁니다 — 윈도우에는 rsync 정식 패키지가 없습니다"
      Write-Info "해결은 스크립트가 아니라 레포 쪽에서 합니다: coco-de/skills 의 install.sh 에 cp -a 폴백을 넣거나 install.ps1 을 추가하면 다음 실행부터 자동 설치됩니다"
      Write-Info "그때까지의 임시 대안: 다른 팀원의 %USERPROFILE%\.claude\skills 폴더를 복사하거나, WSL2에서 install.sh 실행(단 ~/.claude 경로가 갈라져 비권장)"
    } else {
      # ③ install.sh 를 받아 Git Bash로 실행
      $shB64 = ''
      try { $shB64 = ((& gh api repos/coco-de/skills/contents/install.sh --jq .content 2>$null) -join '') } catch { $shB64 = '' }
      if ([string]::IsNullOrWhiteSpace($shB64)) {
        Write-Warn "install.sh를 받지 못했습니다 (coco-de/skills 접근 권한 확인) → 건너뜀"
      } else {
        $tmpSh = Join-Path $env:TEMP 'cocode-skills-install.sh'
        try {
          # BOM·CRLF가 붙으면 shebang과 set -euo pipefail이 깨진다 → 바이트 그대로 기록
          [IO.File]::WriteAllBytes($tmpSh, [Convert]::FromBase64String($shB64))
          $shPath   = ($tmpSh -replace '\\', '/')
          $homePath = ($env:USERPROFILE -replace '\\', '/')
          # HOME 고정: 도메인 PC의 네트워크 홈으로 스킬이 새는 것을 막는다
          # MSYS_NO_PATHCONV=1: Git Bash가 경로를 제멋대로 바꾸지 않게 한다
          $bashLine = "export HOME='$homePath'; export MSYS_NO_PATHCONV=1; bash '$shPath'"
          $out = & $gitBash -lc $bashLine 2>&1
          if ($LASTEXITCODE -ne 0) { Write-Info "install.sh 종료 코드 $LASTEXITCODE — 마지막 메시지: $(($out | Select-Object -Last 2) -join ' / ')" }
        } catch {
          Write-Warn "install.sh 실행 실패: $($_.Exception.Message)"
        } finally {
          Remove-Item $tmpSh -Force -ErrorAction SilentlyContinue
        }
      }
    }
  }

  # ④ 설치 결과 확인 (설치 방식과 무관하게 같은 기준으로 본다)
  $skillsStamp = Join-Path $env:USERPROFILE '.claude\skills\.cocode-skills-version'
  $skillsMarket = Join-Path $env:USERPROFILE '.claude\plugins\marketplaces\cocode-skills\plugins'
  if ((Test-Path $skillsStamp) -or (Test-Path $skillsMarket)) {
    Write-Ok "cocode-skills 팀 플러그인 설치 완료"
  } else {
    Write-Warn "cocode-skills가 설치되지 않았습니다 → 위 안내 확인 후 스크립트를 다시 실행하세요"
  }
}

# ============================================================
# 4. Flutter/Dart 및 클라우드 도구
#    4-a FVM+Flutter · 4-b Dart 글로벌 패키지 · 4-c gcloud · 4-d DCM
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   앱을 만드는 데 꼭 필요한 핵심 도구를 한 번에 깐다.
#     · Flutter/Dart : 앱을 만드는 개발 도구. 버전 관리자 'fvm'을 통해 깔아서, 프로젝트마다
#                      다른 Flutter 버전을 쓸 수 있게 해 둔다.
#     · Dart 글로벌 패키지 : 터미널에서 바로 부르는 보조 도구들(테스트 커버리지 측정,
#                      여러 패키지를 한 레포에 담은 프로젝트 관리, 코드 자동 생성 등).
#     · gcloud       : Google Cloud 를 터미널에서 다루는 도구.
#     · DCM          : Dart 코드 품질 검사 도구.
#
#   [맥과 다른 점 — Windows 라서 더 해줘야 하는 것들]
#   맥은 Homebrew 한 줄이면 끝나지만 Windows 에는 Homebrew 가 없어서 도구마다 설치 경로가
#   다르다(winget · 공식 zip · Chocolatey). 게다가 Windows 에만 있는 '선행 조건' 세 가지를
#   먼저 처리해야 Flutter 가 제대로 돈다:
#     ① 개발자 모드      — 이게 꺼져 있으면 fvm 과 Flutter 가 '바로가기(심볼릭 링크)'를
#                          못 만들어서, 설치는 되는데 빌드만 실패한다.
#     ② 긴 경로 허용     — Windows 기본값인 260자 경로 제한에 Flutter 빌드가 자주 걸린다.
#     ③ git 안전 폴더    — 이게 없으면 fvm 이 엉뚱하게 "unable to find git" 이라고 실패한다.
#   세 가지 모두 '설치 시점'이 아니라 '첫 빌드 시점'에 터지기 때문에, 원인을 찾기가 매우
#   어렵다. 그래서 설치보다 먼저 확인하고 넘어간다.
#
#   [중요 — PATH 는 새 터미널부터 반영된다]
#   Windows 는 맥의 ~/.zshrc 같은 게 없어서 '사용자 환경변수'에 경로를 등록한다.
#   Add-UserPath 헬퍼가 등록과 동시에 현재 창에도 반영해 주지만, 이미 열려 있던 다른
#   터미널·VS Code·Android Studio 에는 반영되지 않는다 — 스크립트가 끝나면 한 번 껐다 켜야 한다.
# ============================================================

# ------------------------------------------------------------
# 4-a. FVM 설치 + 팀 표준 Flutter($TeamFlutterVersion) 글로벌 설정 (+ Windows 선행 조건)
# ------------------------------------------------------------
Write-Step "4-a. FVM 설치 및 Flutter $TeamFlutterVersion 글로벌 설정 (Windows 선행 조건 포함)"

# --- 4-a-1. Windows 선행 조건 ① 개발자 모드 (심볼릭 링크 허용) ---
#   fvm 은 'fvm global <버전>' 을 할 때 바로가기(심볼릭 링크)를 만들고, Flutter 본체도
#   플러그인을 쓰는 앱을 빌드할 때 같은 걸 만든다. 개발자 모드가 꺼져 있으면 둘 다 실패한다.
#   Flutter 가 내는 에러 문구도 "Please enable Developer Mode" 라고 이걸 지목한다.
#   레지스트리 수정은 관리자 권한이 필요하므로, 권한이 없으면 켜는 방법만 알려주고 넘어간다.
$devModeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devModeOn = $false
try {
  $devModeVal = Get-ItemProperty -Path $devModeKey -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
  if ($null -ne $devModeVal -and $devModeVal.AllowDevelopmentWithoutDevLicense -eq 1) { $devModeOn = $true }
} catch {
  $devModeOn = $false
}

if ($devModeOn) {
  Write-Ok "Windows 개발자 모드 이미 켜져 있음 (Flutter·fvm 이 바로가기를 만들 수 있는 상태)"
} elseif (Test-Admin) {
  try {
    if (-not (Test-Path $devModeKey)) { New-Item -Path $devModeKey -Force | Out-Null }
    New-ItemProperty -Path $devModeKey -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -PropertyType DWORD -Force | Out-Null
    $devModeOn = $true
    Write-Ok "Windows 개발자 모드를 켰습니다"
    Write-Info "설정을 완전히 적용하려면 나중에 한 번 재부팅해 주세요"
  } catch {
    Write-Warn "개발자 모드 자동 설정 실패 → 건너뜀 (수동 설정: 시작 메뉴 검색창에 '개발자 설정' 입력 → '개발자 모드' 켜기, 또는 관리자 PowerShell 에서 start ms-settings:developers)"
  }
} else {
  Write-Warn "개발자 모드가 꺼져 있는데 관리자 권한이 없어 켜지 못했습니다 → 건너뜀 (수동 설정: start ms-settings:developers 실행 후 '개발자 모드' 켜기)"
  Write-Info "이걸 켜지 않으면 설치는 끝나도 Flutter 앱 빌드가 실패합니다 — 가장 흔한 Windows 실패 원인입니다"
}

# --- 4-a-2. Windows 선행 조건 ② 긴 경로(260자 제한) 해제 ---
#   Flutter 는 패키지 캐시·자동 생성 코드·Gradle 중간 파일 때문에 경로가 아주 길어진다.
#   Windows 기본 제한(260자)에 걸리면 빌드가 알아보기 어려운 파일 오류로 실패한다.
#   ⚠ 이 값은 프로그램이 시작될 때 한 번 읽히므로, 켜고 나서 재부팅해야 실제로 적용된다.
$longPathKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$longPathsOn = $false
try {
  $longPathVal = Get-ItemProperty -Path $longPathKey -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue
  if ($null -ne $longPathVal -and $longPathVal.LongPathsEnabled -eq 1) { $longPathsOn = $true }
} catch {
  $longPathsOn = $false
}

if ($longPathsOn) {
  Write-Ok "긴 경로(260자 제한) 해제 이미 적용됨"
} elseif (Test-Admin) {
  try {
    New-ItemProperty -Path $longPathKey -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force | Out-Null
    $longPathsOn = $true
    Write-Ok "긴 경로(260자 제한)를 해제했습니다 (재부팅 후 적용)"
  } catch {
    Write-Warn "긴 경로 해제 실패 → 건너뜀 (수동 설정: 관리자 PowerShell 에서 New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force)"
  }
} else {
  Write-Warn "긴 경로 해제에 관리자 권한이 필요해 건너뜁니다 (수동 설정: 관리자 PowerShell 에서 New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force)"
}
Write-Info "작업 폴더는 되도록 짧은 경로에 두세요 (예: C:\src\<레포이름>) — 문서 폴더 아래는 시작부터 경로가 깁니다"

# --- 4-a-3. Windows 선행 조건 ③ git 안전 폴더(safe.directory) ---
#   git 2.35.2 부터 '폴더 주인이 나와 다르면' 접근을 막는 검사가 생겼다. fvm 이 받아 둔
#   Flutter SDK 폴더가 여기에 걸리는데, 겉으로는 엉뚱하게 "unable to find git" 이라고 뜬다.
#   fvm 공식 문서가 안내하는 해결책(모든 폴더를 안전 목록에 등록)을 그대로 적용한다.
if (Test-Cmd 'git') {
  try {
    $safeDirs = & git config --global --get-all safe.directory 2>$null
    if ($safeDirs -contains '*') {
      Write-Ok "git 안전 폴더(safe.directory) 설정 이미 되어 있음"
    } else {
      & git config --global --add safe.directory '*'
      if ($LASTEXITCODE -eq 0) {
        Write-Ok "git 안전 폴더(safe.directory) 설정 완료 — fvm 의 'unable to find git' 오류를 막아 줍니다"
      } else {
        Write-Warn "git 안전 폴더 설정 실패 → 건너뜀 (수동 설정: git config --global --add safe.directory ""*"")"
      }
    }
  } catch {
    Write-Warn "git 안전 폴더 설정 중 오류 → 건너뜀 (수동 설정: git config --global --add safe.directory ""*"")"
  }
} else {
  Write-Warn "git 이 없어 안전 폴더 설정을 건너뜁니다 (fvm 은 git 으로 Flutter 를 받으므로 git 설치가 필수입니다 — 수동 설치: winget install --id Git.Git -e)"
}

# --- 4-a-4. fvm 설치 (공식 zip 내려받기) ---
#   맥의 'brew install fvm' 에 해당하는 단계.
#   Windows 는 공식 문서가 제시하는 방법이 두 가지(Chocolatey · 공식 zip)인데 공식 zip 을 쓴다.
#     · 관리자 권한이 필요 없다.
#     · Chocolatey 방식은 Dart 를 먼저 깔고 소스를 직접 컴파일해서 몇 분씩 걸리고,
#       그 과정에서 딸려 오는 Dart 가 PATH 앞에 끼어들어 다른 패키지 설치를 깨뜨린다.
if (Test-Cmd 'fvm') {
  Write-Ok "fvm 이미 설치됨"
} else {
  # 버전은 GitHub 최신 릴리스를 물어보고, 못 물어보면 검증된 기본값으로 진행한다.
  $fvmVersion = '4.2.0'
  try {
    $fvmRel = Invoke-WebRequest -UseBasicParsing -Uri 'https://api.github.com/repos/leoafarias/fvm/releases/latest' -Headers @{ 'User-Agent' = 'co-mac-win-setup' } -TimeoutSec 20
    $fvmTag = ($fvmRel.Content | ConvertFrom-Json).tag_name
    if ($fvmTag -match '^\d+\.\d+\.\d+$') { $fvmVersion = $fvmTag }
  } catch {
    Write-Info "fvm 최신 버전 조회에 실패해 기본값 $fvmVersion 으로 설치합니다"
  }

  # ARM64 노트북(Snapdragon·Surface)에서는 arm64 파일을 받아야 한다.
  $fvmArch = 'x64'
  # ($ArchIsArm64 는 스크립트 앞부분에서 CIM 으로 판정한다 — PROCESSOR_ARCHITECTURE 는 ARM64 PC 에서
  #  PowerShell 이 x64 호환 모드로 뜨면 AMD64 라고 거짓 보고하므로 쓰지 않는다)
  if ($ArchIsArm64) { $fvmArch = 'arm64' }

  try {
    $fvmDest = Join-Path $env:LOCALAPPDATA 'fvm-bin'
    $fvmZip  = Join-Path $env:TEMP 'fvm.zip'
    $fvmUrl  = "https://github.com/leoafarias/fvm/releases/download/$fvmVersion/fvm-$fvmVersion-windows-$fvmArch.zip"
    New-Item -ItemType Directory -Force -Path $fvmDest | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $fvmUrl -OutFile $fvmZip
    Expand-Archive -Path $fvmZip -DestinationPath $fvmDest -Force

    # 압축 안의 폴더 구조가 바뀌어도 따라갈 수 있도록 fvm.exe 를 찾아서 그 폴더를 등록한다.
    $fvmExe = Get-ChildItem -Path $fvmDest -Filter 'fvm.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $fvmExe) {
      Add-UserPath $fvmExe.DirectoryName -Front
      Write-Ok "fvm $fvmVersion 설치 완료 ($($fvmExe.DirectoryName))"
    } else {
      Write-Warn "내려받은 fvm 안에서 fvm.exe 를 찾지 못했습니다 → 건너뜀 (수동 설치: $fvmUrl 을 받아 압축을 풀고 그 폴더를 PATH 에 추가)"
    }
  } catch {
    Write-Warn "fvm 설치 실패 → 건너뜀 (수동 설치: https://fvm.app/documentation/getting-started/installation)"
  }
}

# --- 4-a-5. 팀 표준 Flutter($TeamFlutterVersion) 설치 + 기본 버전으로 지정 ---
#   맥의 'yes | fvm install <버전>' 에 해당한다. Windows 에는 yes 명령이 없어서, fvm 이
#   'CI 환경에서는 물어보지 않는다'는 성질을 이용해 $env:CI 를 잠깐 켜 두고 실행한다.
#   (이 값을 켜면 fvm 의 내려받기 캐시 최적화도 같이 꺼지므로, 이 단계에서만 켰다 되돌린다)
#   예전에 stable 로 세팅한 PC도 재실행하면 이 버전이 설치되고 기본 버전도 이 버전으로 바뀐다.
if (Test-Cmd 'fvm') {
  $prevCI = $env:CI
  try {
    $env:CI = 'true'

    & fvm install $TeamFlutterVersion
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "Flutter $TeamFlutterVersion 설치 완료"
    } else {
      Write-Warn "Flutter $TeamFlutterVersion 설치 실패 → 건너뜀 (수동 설치: fvm install $TeamFlutterVersion)"
    }

    & fvm global $TeamFlutterVersion --force
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "Flutter $TeamFlutterVersion 을 기본 버전으로 지정했습니다"
    } else {
      Write-Warn "Flutter $TeamFlutterVersion 기본 지정 실패 → 건너뜀 (수동 설정: fvm global $TeamFlutterVersion --force)"
      if (-not $devModeOn) {
        Write-Info "개발자 모드가 꺼져 있어 실패했을 가능성이 큽니다 — 위 안내대로 켠 뒤 다시 실행해 주세요"
      }
    }
  } catch {
    Write-Warn "Flutter $TeamFlutterVersion 설치/지정 중 오류 → 건너뜀 (수동 설치: fvm install $TeamFlutterVersion ; fvm global $TeamFlutterVersion --force)"
  } finally {
    # 원래 값으로 되돌린다 (원래 없던 값이면 아예 지운다)
    if ($null -eq $prevCI) {
      Remove-Item Env:\CI -ErrorAction SilentlyContinue
    } else {
      $env:CI = $prevCI
    }
  }
} else {
  Write-Warn "fvm 이 없어 Flutter $TeamFlutterVersion 설치를 건너뜁니다 (수동 설치: https://fvm.app/documentation/getting-started/installation)"
}

# --- 4-a-6. flutter/dart 와 Dart 도구들의 PATH 등록 ---
#   맥의 'export PATH="$HOME/fvm/default/bin:$PATH"' + PUB_CACHE 설정에 해당한다.
#   ⚠ PUB_CACHE 는 일부러 건드리지 않는다 — Windows 기본값(%LOCALAPPDATA%\Pub\Cache)이
#     이미 올바른 위치이고, 맥처럼 강제로 바꾸면 옛 경로로 잡혀 경고가 뜬다.
#   ⚠ 순서가 중요하다: fvm 기본 버전의 폴더가 맨 앞에 있어야 한다. 다른 경로에 있는 dart
#     (Android Studio 에 딸려 오는 것 등)가 먼저 잡히면, Flutter 가 필요한 패키지 설치가
#     알아보기 어려운 오류로 실패한다. 맥 스크립트의 path_force_front 와 같은 이유다.
$pubCacheBin = Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin'
try { New-Item -ItemType Directory -Force -Path $pubCacheBin | Out-Null } catch { }
Add-UserPath $pubCacheBin -Front

#   fvm 이 실제로 쓰는 폴더는 fvm 에게 직접 물어본다 — 공식 문서와 실제 동작이 서로 다른
#   구간이라, 경로를 그대로 박아 두면 fvm 업데이트 때 조용히 어긋난다.
$fvmDefaultBin = $null
if (Test-Cmd 'fvm') {
  try {
    $fvmCtx = (& fvm api context 2>$null) | Out-String
    $fvmMatch = [regex]::Match($fvmCtx, '"globalCacheBinPath"\s*:\s*"([^"]+)"')
    if ($fvmMatch.Success) { $fvmDefaultBin = $fvmMatch.Groups[1].Value -replace '\\\\', '\' }
  } catch {
    $fvmDefaultBin = $null
  }
}
if ([string]::IsNullOrWhiteSpace($fvmDefaultBin) -or -not (Test-Path $fvmDefaultBin)) {
  # 물어보지 못했으면 알려진 두 후보를 순서대로 확인한다
  $fvmDefaultBin = $null
  foreach ($cand in @((Join-Path $env:USERPROFILE 'fvm\default\bin'), (Join-Path $env:LOCALAPPDATA 'fvm\default\bin'))) {
    if (Test-Path $cand) { $fvmDefaultBin = $cand; break }
  }
}
if ($null -ne $fvmDefaultBin) {
  Add-UserPath $fvmDefaultBin -Front
  Write-Ok "Flutter/Dart 경로를 등록했습니다 ($fvmDefaultBin)"
} else {
  Write-Warn "Flutter 기본 버전 폴더를 찾지 못해 PATH 등록을 건너뜁니다 (수동 확인: fvm global $TeamFlutterVersion --force 실행 후 fvm api context)"
}

# --- 4-a-7. Windows 데스크톱 앱 빌드용 C++ 도구 (Visual Studio Build Tools) ---
#   Windows 용 데스크톱 앱을 빌드하려면 마이크로소프트의 C++ 빌드 도구가 필요하다
#   (맥에서 Xcode 가 필요한 것과 같은 이유). 무거운 Visual Studio 프로그램 전체가 아니라
#   '빌드 도구'만 깔면 충분하다 — Flutter 는 둘 중 아무거나 있으면 통과시킨다.
Write-Step "4-a-7. Windows 앱 빌드 도구 확인 (Visual Studio Build Tools — Flutter 데스크톱 빌드용)"

$vsProgFiles = ${env:ProgramFiles(x86)}
if ([string]::IsNullOrWhiteSpace($vsProgFiles)) { $vsProgFiles = $env:ProgramFiles }
$vsWhere = Join-Path $vsProgFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsFound = $false
if (Test-Path $vsWhere) {
  try {
    $vsPath = & $vsWhere -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' 'Microsoft.VisualStudio.Component.VC.CMake.Project' -property installationPath 2>$null
    if (-not [string]::IsNullOrWhiteSpace(($vsPath | Out-String))) { $vsFound = $true }
  } catch {
    $vsFound = $false
  }
}

if ($vsFound) {
  Write-Ok "Windows 앱 빌드 도구(Visual Studio Build Tools) 이미 설치됨"
} elseif (-not (Test-Cmd 'winget')) {
  Write-Warn "winget 이 없어 Windows 앱 빌드 도구 설치를 건너뜁니다 (수동 설치: https://visualstudio.microsoft.com/downloads/ 에서 'Build Tools for Visual Studio' → 'C++를 사용한 데스크톱 개발' 선택)"
} elseif (-not $CanElevate) {
  # 이 설치는 PC 전체(머신 범위)에 깔리므로 관리자 승인(UAC) 창이 반드시 뜬다.
  # 눌러 줄 사람이 없는 실행(예약 작업·원격 배포·비대화형 재실행)에서는 winget 이 그 창 앞에서 멈춰 버린다.
  Write-Warn "Windows 앱 빌드 도구는 관리자 승인(UAC)이 필요한데 지금은 승인 창을 띄울 수 없어 건너뜁니다"
  Write-Info "수동 설치: 시작 메뉴에서 'Windows Terminal'(또는 PowerShell)을 오른쪽 클릭 > '관리자 권한으로 실행' 한 뒤, 아래 한 줄을 그대로 붙여 넣으세요"
  Write-Info '  winget install --id Microsoft.VisualStudio.2022.BuildTools -e --disable-interactivity --accept-source-agreements --accept-package-agreements --override "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"'
} else {
  Write-Info "Windows 앱 빌드 도구를 설치합니다 — 내려받을 용량이 커서 10~30분 걸릴 수 있고, 관리자 승인 창이 뜹니다"
  try {
    # ⚠ winget 의 --override 는 기본 옵션을 '대체'하므로 조용히 설치되는 옵션을 직접 다 넣어야 한다.
    #   ;includeRecommended 를 붙여야 Windows SDK 등 기본 구성요소가 함께 깔린다.
    $vsArgs = @(
      'install', '--id', 'Microsoft.VisualStudio.2022.BuildTools', '-e',
      '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity',
      '--override', '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended'
    )
    & winget @vsArgs
    $vsExit = $LASTEXITCODE
    # 설치 프로그램의 종료 번호는 0 말고도 정상인 게 있다:
    #   3010 = 설치는 됐고 재부팅만 남음 / 1641 = 재부팅이 시작됨
    #   1618·1001·1003 = 다른 설치가 진행 중 (나중에 다시 실행하면 된다)
    if ($vsExit -eq 0) {
      $vsFound = $true
      Write-Ok "Windows 앱 빌드 도구 설치 완료"
    } elseif ($vsExit -eq 3010 -or $vsExit -eq 1641) {
      $vsFound = $true
      Write-Ok "Windows 앱 빌드 도구 설치 완료 (적용하려면 재부팅이 필요합니다)"
    } elseif ($vsExit -eq 1618 -or $vsExit -eq 1001 -or $vsExit -eq 1003) {
      Write-Warn "다른 설치 작업이 진행 중이라 Windows 앱 빌드 도구를 깔지 못했습니다 → 건너뜀 (그 작업이 끝난 뒤 이 스크립트를 다시 실행해 주세요)"
    } else {
      Write-Warn "Windows 앱 빌드 도구 설치 실패(종료 번호 $vsExit) → 건너뜀 (수동 설치: https://visualstudio.microsoft.com/downloads/ 에서 'Build Tools for Visual Studio' → 'C++를 사용한 데스크톱 개발')"
    }
  } catch {
    Write-Warn "Windows 앱 빌드 도구 설치 중 오류 → 건너뜀 (수동 설치: https://visualstudio.microsoft.com/downloads/ 에서 'Build Tools for Visual Studio' → 'C++를 사용한 데스크톱 개발')"
  }
}

}


# ------------------------------------------------------------
# -DartOnly 사전 점검
#   이 옵션은 "이미 세팅을 마친 PC에서 패키지만" 다시 까는 용도라, Flutter/Dart 까지
#   대신 깔아 주지는 않는다. dart 가 없으면 대신 깔지 말고 복붙할 명령을 알려주고 멈춘다.
#   (맥 스크립트의 --dart-only 와 같은 원칙)
# ------------------------------------------------------------
if ($DartOnly) {
    # fvm 기본 버전 경로를 이 창의 PATH 에 먼저 반영한다 — 새 창을 안 열었어도 dart 를 찾게.
    foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'fvm\default\bin'),
        (Join-Path $env:USERPROFILE 'fvm\default\bin'),
        (Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin')
    )) {
        if (Test-Path -LiteralPath $p) { $env:PATH = "$p;$env:PATH" }
    }

    if (-not (Test-Cmd 'dart')) {
        Write-Host ''
        if (Test-Cmd 'fvm') {
            Write-Host '❌ dart 명령을 찾지 못했습니다 — fvm은 있지만 기본 Flutter 버전이 지정돼 있지 않습니다.' -ForegroundColor Red
            Write-Host '   → 아래를 먼저 실행한 뒤 다시 시도해 주세요:'
            Write-Host "        fvm global $TeamFlutterVersion --force"
            Write-Host '        .\win-setup.ps1 -DartOnly'
        } else {
            Write-Host '❌ dart 명령을 찾지 못했습니다 — Flutter/Dart(fvm)가 아직 준비되지 않은 PC로 보입니다.' -ForegroundColor Red
            Write-Host '   이 옵션은 이미 세팅을 마친 PC에서 패키지만 다시 까는 용도라 전체 설치가 먼저입니다.'
            Write-Host '   → 옵션 없이 실행해 주세요: .\win-setup.ps1'
        }
        exit 1
    }
    # 어떤 dart 로 깔고 있는지 한 줄 남긴다 — 여러 dart 가 섞여 있을 때
    # "왜 어떤 패키지만 실패하지?" 를 이 한 줄로 바로 알 수 있다.
    Write-Info "사용 중인 dart: $((Get-Command dart).Source)"
}


# ══════════════════════════════════════════════════════════════
# 4-b단계 — Dart 글로벌 패키지 (-DartOnly 로도 실행)
# ══════════════════════════════════════════════════════════════
if ($RunInstall -or $DartOnly) {

# ------------------------------------------------------------
# 4-b. Dart 글로벌 패키지
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   Flutter/Dart 로 일할 때 터미널에서 바로 부르는 도구들(테스트 커버리지 측정, 모노레포
#   관리, 코드 템플릿 생성 등)을 컴퓨터 전체에서 쓸 수 있게 깔아 둔다. 프로젝트마다 따로
#   까는 게 아니라 PC 에 한 번 깔아 두고 모든 프로젝트에서 함께 쓰는 도구들이다.
#     기본 패키지  : coverage · melos · mason_cli · flutter_gen · jaspr_cli ·
#                    serverpod_cli · flutterfire_cli  (팀 Makefile 의 목록과 같다)
#     co:code 추가 : marionette_mcp · mcp_server_dart · cob(co-bricks)
# ------------------------------------------------------------
Write-Step "4-b. Dart 글로벌 패키지 설치 (coverage, melos, mason_cli, flutter_gen, jaspr_cli, serverpod_cli, flutterfire_cli + marionette_mcp, mcp_server_dart, cob)"

# 이 섹션 안에서만 쓰는 작은 도우미 — 패키지 하나를 깔고 결과를 한 줄로 알려 준다.
#   'dart pub global activate' 는 이미 깔려 있어도 최신으로 다시 활성화만 하므로
#   몇 번을 실행해도 안전하다(멱등).
function Invoke-DartGlobalActivate {
  param(
    [string]$Package,
    [string]$Constraint
  )
  try {
    if ([string]::IsNullOrWhiteSpace($Constraint)) {
      & dart pub global activate $Package
      $manual = "dart pub global activate $Package"
    } else {
      & dart pub global activate $Package $Constraint
      $manual = "dart pub global activate $Package '$Constraint'"
    }
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "$Package 설치 완료"
    } else {
      Write-Warn "$Package 설치 실패 → 건너뜀 (수동 설치: $manual)"
    }
  } catch {
    Write-Warn "$Package 설치 중 오류 → 건너뜀 (수동 설치: dart pub global activate $Package)"
  }
}

if (-not (Test-Cmd 'dart')) {
  Write-Warn "dart 명령을 찾지 못해 Dart 글로벌 패키지 설치를 통째로 건너뜁니다"
  Write-Info "위 4-a 단계(fvm · Flutter $TeamFlutterVersion)가 성공했는지 확인한 뒤 이 스크립트를 다시 실행해 주세요"
  Write-Info "이미 깔려 있다면 터미널을 완전히 닫았다 새로 열면 인식되는 경우가 많습니다 (PATH 는 새 창부터 반영)"
} else {
  # 어떤 dart 로 깔고 있는지 한 줄 남긴다 — 여러 dart 가 섞여 있을 때
  # "왜 어떤 패키지만 실패하지?" 를 이 한 줄로 바로 알 수 있다.
  Write-Info "사용 중인 dart: $((Get-Command dart).Source)"

  # 버전을 고정하지 않는 기본 패키지들
  foreach ($pkg in @('coverage', 'melos', 'mason_cli', 'flutter_gen', 'jaspr_cli')) {
    Invoke-DartGlobalActivate -Package $pkg
  }

  # serverpod_cli 는 팀이 항상 베타/RC 최신판을 쓴다 — 버전 없이 설치하면 dart pub 이
  # 안정판(예: 3.4.13)만 골라 베타를 건너뛰므로, pub.dev 에서 실제 최신 버전을 조회해
  # 명시 설치한다. versions 배열은 semver 오름차순으로 내려오므로 마지막 항목이 지금
  # 시점 가장 높은 버전 — major 가 올라가도(4→5 등) 손대지 않아도 그대로 따라간다.
  $serverpodLatest = $null
  try {
    $serverpodPkgInfo = Invoke-RestMethod -Uri 'https://pub.dev/api/packages/serverpod_cli' -TimeoutSec 10
    $serverpodLatest = $serverpodPkgInfo.versions[-1].version
  } catch {
    $serverpodLatest = $null
  }
  if ([string]::IsNullOrWhiteSpace($serverpodLatest)) {
    Write-Warn "pub.dev 최신 버전 조회 실패 → serverpod_cli 안정판으로 설치"
    Invoke-DartGlobalActivate -Package 'serverpod_cli'
  } else {
    # 조회한 버전은 순수 숫자(예: 4.0.0-rc.1)라 ^ 같은 특수문자가 없어 따옴표 이슈가 없다.
    Invoke-DartGlobalActivate -Package 'serverpod_cli' -Constraint $serverpodLatest
  }

  # flutterfire_cli: 공개 패키지라 GitHub 인증 없이 바로 깔린다
  #   (실제 'flutterfire configure' 를 쓰려면 Firebase CLI 도 따로 필요하다)
  Invoke-DartGlobalActivate -Package 'flutterfire_cli'

  # 여기부터는 co:code 추가분
  Invoke-DartGlobalActivate -Package 'marionette_mcp'
  Invoke-DartGlobalActivate -Package 'mcp_server_dart'

  # cob(co-bricks)는 사내 비공개 저장소라 GitHub 로그인이 되어 있어야 한다.
  #   로그인이 안 된 상태로 그냥 시도하면 git 이 아이디/비밀번호를 물어보며 멈춘 것처럼
  #   보이므로, 먼저 확인해서 원인을 알 수 있는 안내로 대신한다.
  #   (미검증 — 비공개 저장소라 Windows 에서 실제 설치를 확인하지 못했습니다. 실패 시 수동 설치)
  $ghReady = $false
  if (Test-Cmd 'gh') {
    try {
      & gh auth status 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $ghReady = $true }
    } catch {
      $ghReady = $false
    }
  }

  if (-not $ghReady) {
    Write-Warn "GitHub 인증이 안 돼 있어 cob(co-bricks) 설치를 건너뜁니다 (수동 설치: gh auth login → gh auth setup-git → dart pub global activate --source git https://github.com/coco-de/co-bricks.git)"
  } else {
    $prevGitPrompt = $env:GIT_TERMINAL_PROMPT
    try {
      # git 이 자격증명을 못 찾아도 아이디/비밀번호를 물어보며 멈추지 않게 한다 — 물어보는
      # 대신 바로 실패시켜야 스크립트가 멈춘 것처럼 보이지 않는다.
      $env:GIT_TERMINAL_PROMPT = '0'
      & dart pub global activate --source git https://github.com/coco-de/co-bricks.git
      if ($LASTEXITCODE -eq 0) {
        Write-Ok "cob(co-bricks) 설치 완료"
      } else {
        Write-Warn "cob(co-bricks) 설치 실패 → 건너뜀 (수동 설치: gh auth setup-git 실행 후 dart pub global activate --source git https://github.com/coco-de/co-bricks.git)"
        # Windows 는 Git 에 기본 포함된 자격증명 관리자와 gh 가 서로 부딪히는 일이 있어,
        # 지금 어떤 게 쓰이고 있는지 같이 보여 준다 (원격으로 도와줄 때 이 두 줄이 결정적이다).
        try {
          $credHelpers = (& git config --global --get-all credential.helper 2>$null) | Out-String
          $ghHelper = (& git config --global --get 'credential.https://github.com.helper' 2>$null) | Out-String
          Write-Info "현재 git 자격증명 도우미: $($credHelpers.Trim())"
          Write-Info "github.com 전용 설정: $($ghHelper.Trim())"
        } catch { }
      }
    } catch {
      Write-Warn "cob(co-bricks) 설치 중 오류 → 건너뜀 (수동 설치: gh auth setup-git 실행 후 dart pub global activate --source git https://github.com/coco-de/co-bricks.git)"
    } finally {
      if ($null -eq $prevGitPrompt) {
        Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
      } else {
        $env:GIT_TERMINAL_PROMPT = $prevGitPrompt
      }
    }
  }
}

}



# ══════════════════════════════════════════════════════════════
# 4-c ~ 7.5단계 — gcloud · DCM · Android SDK · 런타임 · 셸/프롬프트/폰트
# ══════════════════════════════════════════════════════════════
if ($RunInstall) {

# ------------------------------------------------------------
# 4-c. Google Cloud CLI (gcloud)
#
#   맥의 'brew install --cask gcloud-cli' 에 해당한다.
#   winget 목록에 올라온 설치 파일 정보가 구글의 실제 최신 파일과 어긋나 실패하는 일이
#   종종 있어서, 실패하면 구글 공식 설치 파일을 직접 받아 조용히 설치하는 길을 하나 더 둔다.
# ------------------------------------------------------------
Write-Step "4-c. Google Cloud CLI 설치"

if (Test-Cmd 'gcloud') {
  Write-Ok "gcloud 이미 설치됨"
} else {
  $gcloudOk = Install-Winget -Id 'Google.CloudSDK' -Name 'Google Cloud CLI (gcloud)' -ProbeCmd 'gcloud'
  if (-not $gcloudOk) {
    Write-Info "winget 설치가 실패해 구글 공식 설치 파일로 다시 시도합니다"
    try {
      $gcloudExe = Join-Path $env:TEMP 'GoogleCloudSDKInstaller.exe'
      Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe' -OutFile $gcloudExe
      # /S = 조용히 설치, /noreporting = 사용 통계 끄기, /nostartmenu·/nodesktop = 바로가기 안 만들기
      #   (/allusers 는 일부러 빼 두었다 — 관리자 권한 없이 내 계정에만 깔면 충분하다)
      Start-Process -FilePath $gcloudExe -ArgumentList '/S', '/noreporting', '/nostartmenu', '/nodesktop' -Wait
      Write-Ok "gcloud 설치 완료 (구글 공식 설치 파일)"
    } catch {
      Write-Warn "gcloud 설치 실패 → 건너뜀 (수동 설치: https://cloud.google.com/sdk/docs/install 에서 Windows 설치 파일 내려받기)"
    }
  }
}

# 설치 프로그램이 등록한 경로는 지금 열려 있는 창에는 반영되지 않는다 — 직접 찾아서 등록해 둔다.
#   (설치 위치가 '내 계정'이냐 '전체 사용자'냐에 따라 달라져서 후보를 순서대로 확인한다)
$gcloudCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin'),
  (Join-Path $env:APPDATA 'Google\Cloud SDK\google-cloud-sdk\bin')
)
if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
  $gcloudCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Google\Cloud SDK\google-cloud-sdk\bin')
}
if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
  $gcloudCandidates += (Join-Path $env:ProgramFiles 'Google\Cloud SDK\google-cloud-sdk\bin')
}
foreach ($gcloudBin in $gcloudCandidates) {
  if (Test-Path $gcloudBin) {
    Add-UserPath $gcloudBin
    break
  }
}

# ------------------------------------------------------------
# 4-d. DCM (Dart Code Metrics)
#
#   Dart 코드 품질 검사 도구. 여기서는 dcm 명령 자체만 깐다 — CI/자동화 인증에 쓰는
#   이메일+키(DCM_EMAIL·DCM_CI_KEY)는 다른 팀 공용 토큰들과 함께 뒤쪽 환경변수 단계에서
#   1Password 로부터 주입한다.
#
#   ⚠ DCM 은 Windows 공식 설치 경로가 Chocolatey 하나뿐이고 winget 에는 없다.
#     Chocolatey 는 관리자 권한이 필요하므로, 이미 깔려 있고 관리자로 실행 중일 때만 쓰고
#     그 외에는 공식 GitHub 배포 파일을 직접 받아 내 계정 폴더에 푼다(관리자 권한 불필요).
#   ⚠ ARM64 노트북에는 전용 빌드가 없어 x64 버전이 호환 모드로 돈다 (동작은 하지만 느릴 수 있음).
# ------------------------------------------------------------
Write-Step "4-d. DCM 설치"

if (Test-Cmd 'dcm') {
  Write-Ok "dcm 이미 설치됨"
} elseif ((Test-Cmd 'choco') -and (Test-Admin)) {
  try {
    & choco install dcm -y
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "dcm 설치 완료 (Chocolatey)"
    } else {
      Write-Warn "dcm 설치 실패 → 건너뜀 (수동 설치: 관리자 PowerShell 에서 choco install dcm -y)"
    }
  } catch {
    Write-Warn "dcm 설치 중 오류 → 건너뜀 (수동 설치: 관리자 PowerShell 에서 choco install dcm -y)"
  }
} else {
  # 버전은 공식 배포 목록에서 최신을 물어보고, 못 물어보면 검증된 기본값으로 진행한다.
  $dcmVersion = '1.39.1'
  try {
    $dcmRel = Invoke-WebRequest -UseBasicParsing -Uri 'https://api.github.com/repos/CQLabs/homebrew-dcm/releases/latest' -Headers @{ 'User-Agent' = 'co-mac-win-setup' } -TimeoutSec 20
    $dcmTag = ($dcmRel.Content | ConvertFrom-Json).tag_name
    if ($dcmTag -match '^\d+\.\d+\.\d+$') { $dcmVersion = $dcmTag }
  } catch {
    Write-Info "dcm 최신 버전 조회에 실패해 기본값 $dcmVersion 으로 설치합니다"
  }

  try {
    $dcmDest = Join-Path $env:LOCALAPPDATA 'dcm'
    $dcmZip  = Join-Path $env:TEMP 'dcm.zip'
    $dcmUrl  = "https://github.com/CQLabs/homebrew-dcm/releases/download/$dcmVersion/dcm-windows-release.zip"
    New-Item -ItemType Directory -Force -Path $dcmDest | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $dcmUrl -OutFile $dcmZip
    Expand-Archive -Path $dcmZip -DestinationPath $dcmDest -Force

    $dcmExe = Get-ChildItem -Path $dcmDest -Filter 'dcm.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $dcmExe) {
      Add-UserPath $dcmExe.DirectoryName
      Write-Ok "dcm $dcmVersion 설치 완료 ($($dcmExe.DirectoryName))"
      if ($ArchIsArm64) {
        Write-Info "이 PC 는 ARM64 라 x64 버전이 호환 모드로 실행됩니다 (동작은 하지만 조금 느릴 수 있습니다)"
      }
    } else {
      Write-Warn "내려받은 dcm 안에서 dcm.exe 를 찾지 못했습니다 → 건너뜀 (수동 설치: $dcmUrl 을 받아 압축을 풀고 그 폴더를 PATH 에 추가)"
    }
  } catch {
    Write-Warn "dcm 설치 실패 → 건너뜀 (수동 설치: https://dcm.dev/docs/getting-started/for-developers/installation/ 또는 관리자 PowerShell 에서 choco install dcm -y)"
  }
}
Write-Info "DCM 인증용 DCM_EMAIL·DCM_CI_KEY 는 뒤쪽 환경변수 단계에서 1Password 로부터 자동 주입됩니다"

# ============================================================
# 4-e. Android SDK / AVD
# ------------------------------------------------------------
# [이 단계가 하는 일]
#   Android Studio(앱)만 깔면 SDK 폴더는 텅 비어 있습니다. 원래는 앱을 처음 실행해
#   "SDK 설치 마법사"를 직접 눌러가며 구성요소를 하나씩 받아야 하는데, 이 단계가 그 과정을
#   전부 명령줄로 대신합니다. 끝나면 flutter doctor · Gradle 빌드 · 에뮬레이터가 바로 돌아갑니다.
#
# [맥(mac-setup.sh)과 다른 점 — 왜 코드가 더 긴가]
#   1) Homebrew가 없다. cmdline-tools를 winget/scoop으로 깔 방법이 아예 없어서
#      (winget 저장소에 패키지가 없고, scoop 것은 SDK를 표준 위치가 아닌 곳에 깐다)
#      구글 공식 zip을 직접 받아 '부트스트랩'으로만 씁니다.
#      → 아래 하드코딩된 빌드번호가 낡아도 괜찮습니다. 그 부트스트랩으로 `cmdline-tools;latest`를
#        다시 설치하므로 최종 결과물은 항상 최신입니다. 팀원이 이 숫자를 쫓아다닐 필요 없습니다.
#   2) `export` 한 줄로 끝나지 않는다. Windows의 사용자 환경변수는 레지스트리에만 기록돼
#      지금 열려 있는 창에는 반영되지 않습니다 → Set-UserEnv/Add-UserPath가 영구+현재 세션을 둘 다 처리.
#   3) `yes | sdkmanager` 관용구가 없다. 라이선스 동의 프롬프트가 6~7번 반복되므로
#      'y'를 여러 줄 적어 둔 임시 파일을 표준입력으로 물려 줍니다.
#   4) 에뮬레이터 가속(WHPX)은 관리자 권한 + 재부팅이 필요해 스크립트가 대신 켜면 안 됩니다.
#      (전체 세팅을 관리자로 돌리면 winget·fvm·pub이 관리자 프로필에 깔려 평소 창에서 안 보입니다)
#      기본은 '진단 + 안내'만 하고, 정말 켜고 싶을 때만 -EnableHyperV / --enable-hyperv 로 요청합니다.
#   5) Windows on ARM(스냅드래곤) 노트북은 구글이 에뮬레이터를 내주지 않습니다.
#      → SDK·NDK·빌드도구는 그대로 깔고, 시스템 이미지·AVD 단계만 건너뛴 뒤 실기기 연결을 안내합니다.
# ============================================================
Write-Step "4-e. Android SDK 구성요소 설치 (cmdline-tools, platform-tools, build-tools, platforms, NDK, AVD)"

# 스크립트 맨 끝 '검증 요약'에서 읽어 갈 값들 — 중간에 실패해도 정의는 되어 있어야 합니다
$AndroidSdkHome  = $null
$AndroidJavaHome = $null
$AndroidNdkHome  = $null
$AndroidAvdName  = $null
$AndroidAccelMsg = '미확인'
$AndroidIsArm64  = $false

# ------------------------------------------------------------
# [이 섹션 전용 helper 1] sdkmanager/avdmanager를 "되묻지 않고" 실행합니다.
#   · PowerShell 5.1에는 `<` 입력 리다이렉트가 없어서 Start-Process -RedirectStandardInput을 씁니다.
#   · 출력은 임시 파일로 받아 화면을 진행률 문자로 도배하지 않고, 필요할 때만 꺼내 봅니다.
#   · sdkmanager.bat의 종료코드는 믿을 수 없습니다(구글 알려진 버그).
#     그래서 성공 판정은 언제나 '파일이 실제로 생겼는지'로 합니다.
# ------------------------------------------------------------
function Invoke-AndroidTool {
    param(
        [string]   $Exe,          # sdkmanager.bat / avdmanager.bat 전체 경로
        [string[]] $Arguments,    # 넘길 인자 (공백이 들어갈 값은 부르는 쪽에서 따옴표까지 포함시킵니다)
        [string]   $StdinFile     # 프롬프트에 자동 응답할 파일 (없으면 $null)
    )
    $out = [pscustomobject]@{ ExitCode = -1; Output = ''; Ok = $false }
    if (-not $Exe) { return $out }
    if (-not (Test-Path -LiteralPath $Exe)) { return $out }
    $stamp   = [guid]::NewGuid().ToString('N')
    $outFile = Join-Path $env:TEMP "android-tool-$stamp.out.log"
    $errFile = Join-Path $env:TEMP "android-tool-$stamp.err.log"
    try {
        $sp = @{
            FilePath               = $Exe
            NoNewWindow            = $true
            Wait                   = $true
            PassThru               = $true
            RedirectStandardOutput = $outFile
            RedirectStandardError  = $errFile
        }
        if ($Arguments -and $Arguments.Count -gt 0) { $sp['ArgumentList'] = $Arguments }
        if ($StdinFile -and (Test-Path -LiteralPath $StdinFile)) { $sp['RedirectStandardInput'] = $StdinFile }
        $proc = Start-Process @sp
        if ($proc) { $out.ExitCode = $proc.ExitCode }
        if (Test-Path -LiteralPath $outFile) {
            $txt = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
            if ($txt) { $out.Output = $txt }
        }
        if ($out.ExitCode -eq 0) { $out.Ok = $true }
    } catch {
        Write-Warn ("Android 도구 실행 중 오류: " + $_.Exception.Message)
    } finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    return $out
}

# ------------------------------------------------------------
# [이 섹션 전용 helper 2] sdkmanager --list 출력을 '깨끗한 줄 목록'으로 바꿉니다.
#   Windows에서는 다운로드 진행률이 CR(캐리지리턴)로 같은 줄을 덮어써서
#   "[====] Loading... platforms;android-36 |" 처럼 줄 앞에 쓰레기가 붙습니다.
#   → 줄 끝 CR을 먼저 떼고, 마지막 CR 뒤쪽만 남깁니다. (순서를 바꾸면 줄이 통째로 지워집니다)
# ------------------------------------------------------------
function ConvertTo-CleanSdkLines {
    param([string] $RawText)
    $result = New-Object System.Collections.ArrayList
    if (-not $RawText) { return @() }
    foreach ($ln in ($RawText -split "`n")) {
        $s = ([string]$ln).TrimEnd([char]13)
        $s = $s -replace '^.*\r', ''
        [void]$result.Add($s)
    }
    return $result.ToArray()
}

# ------------------------------------------------------------
# [이 섹션 전용 helper 3] 쓸 만한 JDK 17 이상이 이미 있는지 찾습니다.
#   sdkmanager/avdmanager는 자바로 도는데, cmdline-tools는 자바 17로 컴파일돼 있어
#   자바 11 이하에서는 UnsupportedClassVersionError로 바로 죽습니다.
#   JAVA_HOME은 JDK '루트' 폴더를 가리켜야 합니다(\bin 이 붙어 있으면 안 됩니다).
# ------------------------------------------------------------
function Resolve-AndroidJdkHome {
    $candidates = New-Object System.Collections.ArrayList
    if ($env:JAVA_HOME) { [void]$candidates.Add($env:JAVA_HOME) }
    foreach ($scope in @('User', 'Machine')) {
        try {
            $v = [Environment]::GetEnvironmentVariable('JAVA_HOME', $scope)
            if ($v) { [void]$candidates.Add($v) }
        } catch { }
    }
    # JAVA_HOME을 안 잡아 주는 배포판을 대비해 표준 설치 폴더도 훑습니다
    $roots = @(
        (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
        (Join-Path $env:ProgramFiles 'Java'),
        (Join-Path $env:ProgramFiles 'Microsoft')
    )
    foreach ($root in $roots) {
        if (-not $root) { continue }
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match 'jdk[-_]?(1[7-9]|2[0-9])' } |
                  Sort-Object Name)
        foreach ($d in $dirs) { [void]$candidates.Add($d.FullName) }
    }
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $trimmed = ([string]$c).TrimEnd('\')
        if ($trimmed -match '\\bin$') { $trimmed = Split-Path $trimmed -Parent }
        if (Test-Path -LiteralPath (Join-Path $trimmed 'bin\java.exe')) { return $trimmed }
    }
    return $null
}

try {
    # --------------------------------------------------------
    # (1) SDK 설치 위치 결정
    #   공식 기본 위치는 %LOCALAPPDATA%\Android\Sdk 입니다. Android Studio(GUI)도 같은 곳을 잡으므로
    #   GUI와 명령줄이 SDK를 공유합니다 (맥의 ~/Library/Android/sdk 와 1:1 대응).
    #   ⚠ 다만 이 경로에는 Windows 사용자 이름이 그대로 들어갑니다. 이름에 공백이나 한글이 있으면
    #     sdkmanager.bat이 경로를 잘못 잘라 읽어 통째로 실패하므로, 그럴 때만 C:\Android\Sdk 로 피합니다.
    # --------------------------------------------------------
    $sdkBase = $env:LOCALAPPDATA
    if (-not $sdkBase) { $sdkBase = Join-Path $env:USERPROFILE 'AppData\Local' }
    $sdk = Join-Path $sdkBase 'Android\Sdk'
    if (($sdk -match '\s') -or ($sdk -match '[^\x20-\x7E]')) {
        $fallbackSdk = "$env:SystemDrive\Android\Sdk"
        Write-Warn "사용자 폴더 경로에 공백이나 한글이 있어 Android 도구가 깨질 수 있습니다 → $fallbackSdk 에 설치합니다"
        Write-Info "나중에 Android Studio가 SDK 위치를 물어보면 이 경로를 골라 주세요: $fallbackSdk"
        $sdk = $fallbackSdk
    }
    New-Item -ItemType Directory -Force -Path $sdk -ErrorAction SilentlyContinue | Out-Null
    $AndroidSdkHome = $sdk
    Write-Info "SDK 위치: $sdk"

    # 환경변수는 영구(레지스트리) + 현재 세션 양쪽에 설정합니다.
    #   ANDROID_HOME이 공식 권장이고 ANDROID_SDK_ROOT는 사용 중단 예정이지만,
    #   Flutter·구버전 Gradle·emulator가 아직 후자를 읽으므로 맥 스크립트처럼 둘 다 같은 값으로 맞춥니다.
    #   (두 값이 서로 다르면 Android Gradle Plugin이 경고를 냅니다)
    Set-UserEnv 'ANDROID_HOME' $sdk
    Set-UserEnv 'ANDROID_SDK_ROOT' $sdk

    # --------------------------------------------------------
    # (2) JDK 17 확보 — Android 명령줄 도구는 자바로 돕니다
    #   Temurin(Eclipse Adoptium)을 쓰는 이유: 설치 프로그램이 JAVA_HOME과 PATH를 알아서 잡아 줍니다.
    #   (Microsoft.OpenJDK.17은 무인 설치 시 JAVA_HOME을 안 잡는 알려진 이슈가 있습니다)
    # --------------------------------------------------------
    $AndroidJavaHome = Resolve-AndroidJdkHome
    if ($AndroidJavaHome) {
        Write-Ok "JDK 이미 설치됨 ($AndroidJavaHome)"
    } else {
        Write-Info "Android 도구를 돌리는 데 필요한 자바(JDK 17)를 설치합니다"
        [void](Install-Winget -Id 'EclipseAdoptium.Temurin.17.JDK' -Name 'Temurin JDK 17')
        $AndroidJavaHome = Resolve-AndroidJdkHome
    }
    if ($AndroidJavaHome) {
        Set-UserEnv 'JAVA_HOME' $AndroidJavaHome
        Add-UserPath (Join-Path $AndroidJavaHome 'bin') -Front
    } else {
        Write-Warn "JDK를 찾지 못해 Android SDK 단계를 건너뜁니다 (수동 설치: winget install --exact --id EclipseAdoptium.Temurin.17.JDK)"
    }

    if ($AndroidJavaHome) {
        # ----------------------------------------------------
        # (3) CPU 종류 판정 (일반 x64 PC인가, ARM64 노트북인가)
        #   ⚠ $env:PROCESSOR_ARCHITECTURE는 쓰면 안 됩니다. ARM64 기기에서 PowerShell이
        #     x64 호환 모드로 뜨면 'AMD64'라고 거짓 보고합니다.
        #     기기 자체를 봐야 하므로 WMI/CIM(Win32_ComputerSystem·Win32_Processor)을 씁니다.
        # ----------------------------------------------------
        try {
            $sysType = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).SystemType
            $cpuArch = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Architecture
            if (($sysType -match 'ARM64') -or ($cpuArch -eq 12)) { $AndroidIsArm64 = $true }
        } catch {
            Write-Info "CPU 종류를 확인하지 못해 일반 x64 PC로 간주하고 진행합니다"
        }
        $abi = 'x86_64'
        if ($AndroidIsArm64) { $abi = 'arm64-v8a' }
        Write-Info "CPU: $abi"

        # ----------------------------------------------------
        # (4) cmdline-tools 확보 (sdkmanager / avdmanager 본체)
        #   맥은 brew 것을 '부트스트랩'으로만 쓰고 최신본을 SDK 안에 정식 설치합니다.
        #   Windows에는 brew가 없으니 구글 공식 zip이 그 부트스트랩 역할을 합니다.
        #   부트스트랩은 임시 폴더에 풀어 둡니다 — SDK 안에서 자기 자신을 덮어쓰면
        #   실행 중인 파일이 잠겨 설치가 실패할 수 있기 때문입니다.
        #
        #   최종 구조는 반드시 %ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat 여야 합니다.
        #   (zip을 그냥 풀면 cmdline-tools\bin 이 되는데, 그러면 도구가 SDK 루트를 잘못 계산합니다)
        # ----------------------------------------------------
        $cltDir       = Join-Path $sdk 'cmdline-tools\latest'
        $sdkManager   = Join-Path $cltDir 'bin\sdkmanager.bat'
        $avdManager   = Join-Path $cltDir 'bin\avdmanager.bat'
        $yesFile      = Join-Path $env:TEMP 'android-sdk-yes.txt'
        # 라이선스 동의 프롬프트가 여러 번 반복되므로 'y'를 넉넉히 적어 둡니다 (맥의 `yes |` 대체)
        (1..30 | ForEach-Object { 'y' }) | Set-Content -LiteralPath $yesFile -Encoding Ascii

        if (Test-Path -LiteralPath $sdkManager) {
            Write-Ok "cmdline-tools 이미 설치됨 ($cltDir)"
        } else {
            # 부트스트랩용 빌드번호입니다. 낡아도 괜찮습니다 — 바로 아래에서 최신본으로 갈아끼웁니다.
            $cltBuild = '15859902'
            $cltZip   = Join-Path $env:TEMP "commandlinetools-win-$cltBuild.zip"
            $cltTmp   = Join-Path $env:TEMP 'android-clt-bootstrap'
            $bootstrapMgr = $null
            try {
                if (-not (Test-Path -LiteralPath $cltZip)) {
                    Write-Info "Android 명령줄 도구를 내려받는 중입니다 (약 150MB, 회선에 따라 몇 분 걸릴 수 있습니다)"
                    # 진행바를 끄지 않으면 대용량 다운로드가 비정상적으로 느려집니다(PowerShell 알려진 성능 문제)
                    $prevProgress = $ProgressPreference
                    $ProgressPreference = 'SilentlyContinue'
                    try {
                        # 사내 프록시/TLS 검사 환경 대비
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    } catch { }
                    try {
                        Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-${cltBuild}_latest.zip" `
                            -OutFile $cltZip -UseBasicParsing
                    } finally {
                        $ProgressPreference = $prevProgress
                    }
                }
                if (Test-Path -LiteralPath $cltZip) {
                    Remove-Item -LiteralPath $cltTmp -Recurse -Force -ErrorAction SilentlyContinue
                    Expand-Archive -LiteralPath $cltZip -DestinationPath $cltTmp -Force
                    $bootstrapMgr = Join-Path $cltTmp 'cmdline-tools\bin\sdkmanager.bat'
                }
            } catch {
                Write-Warn ("Android 명령줄 도구 내려받기 실패 → 건너뜁니다 (" + $_.Exception.Message + ")")
                Write-Info "수동 설치: https://developer.android.com/studio 아래쪽 'Command line tools only' zip을 받아 $cltDir 에 풀어 주세요"
            }

            if ($bootstrapMgr -and (Test-Path -LiteralPath $bootstrapMgr)) {
                # 부트스트랩으로 '정식 최신본'을 SDK 안에 설치합니다 → 위 빌드번호가 낡아도 결과물은 최신
                [void](Invoke-AndroidTool -Exe $bootstrapMgr -Arguments @(('--sdk_root="{0}"' -f $sdk), '--licenses') -StdinFile $yesFile)
                [void](Invoke-AndroidTool -Exe $bootstrapMgr -Arguments @(('--sdk_root="{0}"' -f $sdk), '"cmdline-tools;latest"') -StdinFile $yesFile)
            }

            if (-not (Test-Path -LiteralPath $sdkManager)) {
                # 최신본 승격이 안 됐으면(네트워크·라이선스 문제 등) 받아 둔 zip 내용을 그대로 제자리에 놓습니다.
                # 버전이 조금 낡아도 SDK 구성은 계속 진행할 수 있습니다.
                $extracted = Join-Path $cltTmp 'cmdline-tools'
                if (Test-Path -LiteralPath $extracted) {
                    try {
                        New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') -ErrorAction SilentlyContinue | Out-Null
                        Copy-Item -LiteralPath $extracted -Destination $cltDir -Recurse -Force
                        Write-Info "최신본 승격에 실패해 내려받은 버전을 그대로 사용합니다"
                    } catch {
                        Write-Warn ("cmdline-tools 배치 실패 → 건너뜁니다 (" + $_.Exception.Message + ")")
                    }
                }
            }
            if (Test-Path -LiteralPath $sdkManager) { Write-Ok "cmdline-tools 설치 완료 ($cltDir)" }
        }

        # PATH 등록 — 새 터미널에서 adb·sdkmanager·emulator를 바로 부를 수 있게 합니다
        Add-UserPath (Join-Path $sdk 'cmdline-tools\latest\bin')
        Add-UserPath (Join-Path $sdk 'platform-tools')
        Add-UserPath (Join-Path $sdk 'emulator')

        if (-not (Test-Path -LiteralPath $sdkManager)) {
            Write-Warn "sdkmanager를 찾을 수 없어 Android SDK 구성요소 설치를 건너뜁니다 (Android Studio 첫 실행 마법사로 수동 설치 가능)"
        } else {
            # ------------------------------------------------
            # (5) SDK 라이선스 자동 동의 (맥의 `yes | sdkmanager --licenses` 대체)
            #   성공 판정은 종료코드가 아니라 licenses 폴더에 파일이 생겼는지로 합니다.
            # ------------------------------------------------
            [void](Invoke-AndroidTool -Exe $sdkManager -Arguments @(('--sdk_root="{0}"' -f $sdk), '--licenses') -StdinFile $yesFile)
            $licCount = @(Get-ChildItem -LiteralPath (Join-Path $sdk 'licenses') -File -ErrorAction SilentlyContinue).Count
            if ($licCount -ge 2) {
                Write-Ok "Android SDK 라이선스 동의 완료 (${licCount}건)"
            } else {
                Write-Warn "라이선스 자동 동의를 확인하지 못했습니다 → 계속 진행합니다 (수동: sdkmanager --licenses 실행 후 y 반복 입력)"
            }

            # ------------------------------------------------
            # (6) 설치할 패키지를 '실제로 배포 중인 것' 중에서 고릅니다
            #   맥과 같은 원칙: 목록에서 최신 안정 버전을 찾아 쓰고, 프리뷰(rc/beta)는 제외합니다.
            #   정규식이 `\s*\|` 로 끝나는 이유: --list 출력이 `경로 | 버전 | 설명` 표 형식이라
            #   파이프 문자까지 확인하면 android-37.2-beta3 같은 프리뷰 항목이 자연히 걸러집니다.
            # ------------------------------------------------
            Write-Info "설치 가능한 패키지 목록을 확인하는 중입니다"
            $listRaw   = (Invoke-AndroidTool -Exe $sdkManager -Arguments @(('--sdk_root="{0}"' -f $sdk), '--list')).Output
            $listLines = @(ConvertTo-CleanSdkLines -RawText $listRaw)

            # 최신 안정 platform (예: platforms;android-36)
            $platformPkg  = $null
            $bestPlatform = -1
            foreach ($ln in $listLines) {
                $m = [regex]::Match([string]$ln, '^\s*(platforms;android-(\d+))\s*\|')
                if ($m.Success) {
                    $n = [int]$m.Groups[2].Value
                    if ($n -gt $bestPlatform) { $bestPlatform = $n; $platformPkg = $m.Groups[1].Value }
                }
            }

            # 최신 안정 build-tools
            #   글자 순서로 비교하면 "36.0.0" 이 "9.0.0" 보다 작다고 나오므로 반드시 버전으로 비교합니다.
            $buildToolsPkg  = $null
            $bestBuildTools = $null
            foreach ($ln in $listLines) {
                $m = [regex]::Match([string]$ln, '^\s*(build-tools;(\d+\.\d+\.\d+))\s*\|')
                if ($m.Success) {
                    $v = $null
                    try { $v = [version]$m.Groups[2].Value } catch { $v = $null }
                    if ($v) {
                        if (($null -eq $bestBuildTools) -or ($v -gt $bestBuildTools)) {
                            $bestBuildTools = $v
                            $buildToolsPkg  = $m.Groups[1].Value
                        }
                    }
                }
            }

            # 에뮬레이터 시스템 이미지는 최신 platform보다 늦게 나오기도 합니다
            # (platform은 android-37이 있는데 이미지는 아직 미출시인 경우).
            # 최신 platform 번호를 그대로 쓰면 없는 이미지를 받으려다 AVD 생성까지 실패하므로,
            # '실제로 존재하는' google_apis 이미지 중 가장 최신 API 버전을 고릅니다. (맥과 동일한 로직)
            $systemImagePkg = $null
            $imageApi = 0
            if (-not $AndroidIsArm64) {
                $imgPattern = '^\s*system-images;android-(\d+);google_apis;' + [regex]::Escape($abi) + '\s*\|'
                foreach ($ln in $listLines) {
                    $m = [regex]::Match([string]$ln, $imgPattern)
                    if ($m.Success) {
                        $n = [int]$m.Groups[1].Value
                        if ($n -gt $imageApi) { $imageApi = $n }
                    }
                }
                if ($imageApi -gt 0) { $systemImagePkg = "system-images;android-$imageApi;google_apis;$abi" }
            }

            # NDK는 '목록상 최신'이 아니라 Flutter가 요구하는 버전으로 고정합니다.
            # (목록 최신값은 프리뷰인 경우가 많아 그대로 깔면 Gradle 빌드에서 NDK 버전 불일치 오류가 납니다)
            $ndkDefault = 'ndk;28.2.13676358'   # Flutter 핀을 못 읽을 때 쓰는 검증된 기본값 (맥과 동일)
            $ndkPkg     = $ndkDefault
            $flutterRoot = $null
            if (Test-Cmd 'flutter') {
                try {
                    # 최초 실행이면 Dart SDK 캐시를 받느라 수십 초 걸릴 수 있습니다
                    $fvOut = (& flutter --version --machine 2>$null | Out-String)
                    # "Waiting for another flutter command..." 같은 비-JSON 줄이 앞에 섞일 수 있어 첫 '{' 부터 자릅니다
                    $brace = $fvOut.IndexOf('{')
                    if ($brace -ge 0) {
                        $fvJson = $fvOut.Substring($brace) | ConvertFrom-Json
                        if ($fvJson.flutterRoot) { $flutterRoot = $fvJson.flutterRoot }
                    }
                } catch { $flutterRoot = $null }
            }
            # fvm의 Windows 기본 위치 (맥의 ~/fvm/default 에 대응)
            if (-not $flutterRoot) { $flutterRoot = Join-Path $env:USERPROFILE 'fvm\default' }
            $gradleUtils = Join-Path $flutterRoot 'packages\flutter_tools\lib\src\android\gradle_utils.dart'
            if (Test-Path -LiteralPath $gradleUtils) {
                try {
                    $hit = @(Select-String -LiteralPath $gradleUtils -Pattern "ndkVersion\s*=\s*'([\d.]+)'" -ErrorAction SilentlyContinue) | Select-Object -First 1
                    if ($hit) { $ndkPkg = 'ndk;' + $hit.Matches[0].Groups[1].Value }
                } catch { }
            }
            if ($ndkPkg -eq $ndkDefault) {
                Write-Info "NDK: Flutter 요구 버전을 못 읽어 검증된 기본값을 씁니다 → $ndkPkg"
            } else {
                Write-Info "NDK: Flutter가 요구하는 버전을 씁니다 → $ndkPkg"
            }

            $packages = New-Object System.Collections.ArrayList
            [void]$packages.Add('platform-tools')
            if (-not $AndroidIsArm64) { [void]$packages.Add('emulator') }
            if ($buildToolsPkg)  { [void]$packages.Add($buildToolsPkg) }
            if ($platformPkg)    { [void]$packages.Add($platformPkg) }
            if ($systemImagePkg) { [void]$packages.Add($systemImagePkg) }
            if ($ndkPkg)         { [void]$packages.Add($ndkPkg) }

            Write-Info ("설치할 패키지: " + ($packages -join ' '))
            # 하나씩 설치합니다 — 한 패키지가 실패해도 나머지는 계속 깔리게 하려는 것입니다 (맥과 동일)
            foreach ($pkg in $packages) {
                [void](Invoke-AndroidTool -Exe $sdkManager -Arguments @(('--sdk_root="{0}"' -f $sdk), ('"{0}"' -f $pkg)) -StdinFile $yesFile)
            }

            # 실제로 깔렸는지는 파일 존재로 확인합니다 (sdkmanager 종료코드는 믿을 수 없습니다)
            if (Test-Path -LiteralPath (Join-Path $sdk 'platform-tools\adb.exe')) {
                Write-Ok "platform-tools 설치됨 (adb)"
            } else {
                Write-Warn "platform-tools 설치를 확인하지 못했습니다 (수동: sdkmanager platform-tools)"
            }

            # ------------------------------------------------
            # (7) ANDROID_NDK_HOME — 실제로 디스크에 있는 폴더를 가리키게 합니다
            #   (요구 버전이 깔렸으면 그것을, 아니면 설치된 것 중 가장 최신을 씁니다)
            # ------------------------------------------------
            $wantNdk = $ndkPkg -replace '^ndk;', ''
            $ndkPath = Join-Path $sdk ('ndk\' + $wantNdk)
            if (-not (Test-Path -LiteralPath $ndkPath)) {
                $ndkPath = $null
                $installedNdk = @(Get-ChildItem -LiteralPath (Join-Path $sdk 'ndk') -Directory -ErrorAction SilentlyContinue)
                $newest = $null
                foreach ($d in $installedNdk) {
                    $v = $null
                    try { $v = [version]$d.Name } catch { $v = $null }
                    if ($v) {
                        if (($null -eq $newest) -or ($v -gt $newest.Ver)) {
                            $newest = [pscustomobject]@{ Ver = $v; Path = $d.FullName }
                        }
                    }
                }
                if ($newest) { $ndkPath = $newest.Path }
            }
            if ($ndkPath) {
                $AndroidNdkHome = $ndkPath
                Set-UserEnv 'ANDROID_NDK_HOME' $ndkPath
                Write-Ok "NDK 설치됨 ($ndkPath)"
            } else {
                Write-Warn "NDK 설치를 확인하지 못했습니다 → 건너뜁니다 (수동: sdkmanager `"$ndkPkg`")"
            }

            # ------------------------------------------------
            # (8) AVD(에뮬레이터용 가상 기기) 생성
            #   ARM64 노트북에서는 만들지 않습니다 — 구글이 Windows용 ARM64 에뮬레이터를 배포하지 않아
            #   만들어 봐야 실행이 안 됩니다. 대신 실기기(안드로이드 폰)를 USB로 연결해 쓰면 됩니다.
            # ------------------------------------------------
            if ($AndroidIsArm64) {
                Write-Info "ARM64(스냅드래곤) 노트북이라 에뮬레이터·AVD 단계를 건너뜁니다"
                Write-Info "안드로이드 실기기를 USB로 연결하고 '개발자 옵션 > USB 디버깅'을 켜서 쓰시면 됩니다 (연결 확인: adb devices)"
            } elseif (-not $systemImagePkg) {
                Write-Warn "$abi 용 google_apis 시스템 이미지를 찾지 못해 AVD 생성을 건너뜁니다 (Android Studio의 Device Manager에서 수동 생성 가능)"
            } elseif (-not (Test-Path -LiteralPath $avdManager)) {
                Write-Warn "avdmanager를 찾을 수 없어 AVD 생성을 건너뜁니다 (Android Studio의 Device Manager에서 수동 생성 가능)"
            } else {
                $avdName  = "Pixel_6_API_$imageApi"
                $existing = (Invoke-AndroidTool -Exe $avdManager -Arguments @('list', 'avd')).Output
                if ($existing -and ($existing -match [regex]::Escape($avdName))) {
                    Write-Ok "AVD($avdName) 이미 존재"
                    $AndroidAvdName = $avdName
                } else {
                    # "커스텀 하드웨어 프로필을 만들까요?" 프롬프트에 no로 답합니다
                    # (--force 를 함께 주면 대개 묻지도 않아서 비대화형에서 더 안정적입니다)
                    $noFile = Join-Path $env:TEMP 'android-avd-no.txt'
                    (1..5 | ForEach-Object { 'no' }) | Set-Content -LiteralPath $noFile -Encoding Ascii
                    [void](Invoke-AndroidTool -Exe $avdManager `
                        -Arguments @('create', 'avd', '-n', $avdName, '-k', ('"{0}"' -f $systemImagePkg), '-d', 'pixel_6', '--force') `
                        -StdinFile $noFile)
                    $after = (Invoke-AndroidTool -Exe $avdManager -Arguments @('list', 'avd')).Output
                    if ($after -and ($after -match [regex]::Escape($avdName))) {
                        Write-Ok "AVD 생성 완료 ($avdName)"
                        $AndroidAvdName = $avdName
                    } else {
                        Write-Warn "AVD 생성 실패 → 건너뜁니다 (Android Studio의 Device Manager에서 수동 생성 가능)"
                    }
                }
            }

            # ------------------------------------------------
            # (9) 에뮬레이터 하드웨어 가속 진단 — Windows에만 있는 단계입니다
            #   (맥은 OS가 알아서 해 주기 때문에 mac-setup.sh에는 이 단계가 없습니다)
            #   가속이 꺼져 있으면 에뮬레이터가 아예 안 뜨거나 숨막히게 느립니다.
            #   ⚠ 켜는 작업(WHPX 활성화)은 관리자 권한 + 재부팅이 필요해 스크립트가 마음대로 하지 않습니다.
            #     전체 세팅을 관리자로 돌리면 winget·fvm·pub 설치가 관리자 프로필에 깔려
            #     평소 쓰는 터미널에서 안 보이는 2차 사고가 나기 때문입니다.
            #   그래서 기본은 '상태를 알려 주고 켜는 방법을 안내'까지만 합니다.
            # ------------------------------------------------
            if ($AndroidIsArm64) {
                $AndroidAccelMsg = 'ARM64 — 에뮬레이터 미지원 (실기기 사용)'
            } else {
                $emuExe = Join-Path $sdk 'emulator\emulator.exe'
                if (-not (Test-Path -LiteralPath $emuExe)) {
                    $AndroidAccelMsg = '에뮬레이터 미설치'
                    Write-Info "에뮬레이터가 설치되지 않아 가속 진단을 건너뜁니다"
                } else {
                    $accelOut = ''
                    try { $accelOut = (& $emuExe -accel-check 2>&1 | Out-String) } catch { $accelOut = '' }
                    if ($accelOut -match 'installed and usable') {
                        $AndroidAccelMsg = '사용 가능 (WHPX)'
                        Write-Ok "에뮬레이터 하드웨어 가속 사용 가능"
                    } else {
                        $AndroidAccelMsg = '꺼짐 — 관리자 PowerShell에서 WHPX 활성화 후 재부팅 필요'
                        Write-Warn "에뮬레이터 하드웨어 가속이 꺼져 있습니다 → 에뮬레이터가 안 뜨거나 매우 느릴 수 있습니다"
                        Write-Info "켜는 방법 1: '관리자 권한으로 실행'한 PowerShell에서 아래 한 줄을 실행하고 PC를 다시 시작"
                        Write-Info "    Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart"
                        Write-Info "켜는 방법 2: 관리자 PowerShell에서  .\win-setup.ps1 -EnableHyperV  (전체 설치 없이 가속만 켜고 끝납니다)"
                        Write-Info "그래도 안 되면 PC를 껐다 켜며 BIOS/UEFI에 들어가 'Intel VT-x' 또는 'AMD SVM'을 켜 주세요 (이건 프로그램이 대신 켤 수 없습니다)"

                        # 사용자가 명시적으로 요청했고(-EnableHyperV / --enable-hyperv) 관리자 권한일 때만 실제로 켭니다
                        $wantHyperV = $false
                        $hvVar = Get-Variable -Name 'EnableHyperV' -ErrorAction SilentlyContinue
                        if ($hvVar -and $hvVar.Value) { $wantHyperV = $true }
                        if ($args -and ($args -contains '--enable-hyperv')) { $wantHyperV = $true }

                        if ($wantHyperV) {
                            if (-not (Test-Admin)) {
                                Write-Warn "-EnableHyperV 는 관리자 권한이 필요합니다 → 건너뜁니다 (PowerShell을 '관리자 권한으로 실행'한 뒤 다시 시도해 주세요)"
                            } else {
                                try {
                                    Write-Info "WHPX(Windows Hypervisor Platform)를 켜는 중입니다"
                                    Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart -ErrorAction Stop | Out-Null
                                    $AndroidAccelMsg = '활성화됨 — 재부팅 후 적용'
                                    Write-Ok "WHPX 활성화 완료 — PC를 다시 시작해야 적용됩니다"
                                } catch {
                                    Write-Warn ("WHPX 활성화 실패 → 건너뜁니다 (수동: DISM /Online /Enable-Feature /FeatureName:HypervisorPlatform /All /NoRestart) — " + $_.Exception.Message)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
} catch {
    Write-Warn ("Android SDK 단계에서 예상치 못한 오류가 나 건너뜁니다: " + $_.Exception.Message)
    Write-Info "수동 대안: Android Studio를 실행해 첫 실행 마법사(SDK Manager)로 SDK·NDK·에뮬레이터를 설치할 수 있습니다"
}

# ============================================================
# 5 · 6 · 6.5. 런타임 설치 (Python · Node.js) + Claude Code 상태줄
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   개발에 필요한 두 가지 실행 환경을 깔고, 버전을 바꿔 쓸 수 있게 관리 도구까지 넣습니다.
#     · Python  → pyenv-win  (맥의 pyenv)
#     · Node.js → nvm-windows (맥의 nvm)
#   이름은 같아 보여도 윈도우판은 동작 방식이 꽤 달라서, 차이를 아래 주석에 적어 두었습니다.
# ------------------------------------------------------------
Write-Step "5. Python 최신 3.x 설치 (pyenv-win)"

$pyenvRoot = Join-Path $env:USERPROFILE '.pyenv'
$pyenvBat = Join-Path $pyenvRoot 'pyenv-win\bin\pyenv.bat'

if (Test-Path -LiteralPath $pyenvBat) {
    Write-Ok "pyenv-win 이미 설치됨"
}
else {
    try {
        $pyenvInstaller = Join-Path $env:TEMP 'install-pyenv-win.ps1'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1' -OutFile $pyenvInstaller -ErrorAction Stop
        Unblock-File -LiteralPath $pyenvInstaller -ErrorAction SilentlyContinue
        & $pyenvInstaller
        if (Test-Path -LiteralPath $pyenvBat) { Write-Ok "pyenv-win 설치 완료" }
        else { Write-Warn "pyenv-win 설치를 확인하지 못했습니다 → 건너뜀 (수동 설치: https://github.com/pyenv-win/pyenv-win#installation)" }
    }
    catch {
        Write-Warn "pyenv-win 설치 실패 → 건너뜀 (수동 설치: https://github.com/pyenv-win/pyenv-win#installation)"
    }
}

# pyenv-win 설치 스크립트는 PATH를 다루는 방식이 안전하지 않아 값 형식이 망가질 수 있습니다.
# (%USERPROFILE% 같은 표기가 든 항목이 깨지는 문제) → 형식만 원래대로 되돌려 놓습니다.
try {
    $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if ($envKey) {
        try {
            $pathKind = $envKey.GetValueKind('Path')
            if ($pathKind -eq [Microsoft.Win32.RegistryValueKind]::String) {
                $rawPath = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $envKey.SetValue('Path', $rawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
                Write-Info "사용자 PATH 값 형식을 되돌렸습니다 (%USERPROFILE% 같은 표기가 깨지지 않도록 보정)"
            }
        }
        catch { }
        finally { $envKey.Close() }
    }
}
catch {
    Write-Info "사용자 PATH 형식 검사를 건너뜁니다 (설치에는 영향이 없습니다)"
}

if (Test-Path -LiteralPath $pyenvBat) {
    # 설치 직후에는 지금 창에서 pyenv가 안 잡히므로, 경로를 등록해 두고 절대경로로 부릅니다.
    # ⚠ 반드시 PATH '맨 앞'(-Front)에 넣습니다. 뒤에 붙이면 %LOCALAPPDATA%\Microsoft\WindowsApps 안의
    #   python 앱 실행 별칭 스텁이 먼저 잡혀, 새 터미널에서 python 을 칠 때 Microsoft Store 안내 창이 뜹니다.
    #   (shims 를 먼저, bin 을 나중에 맨 앞으로 넣어 최종 순서가 'bin → shims' 가 되게 합니다 — 3.5단계와 동일)
    $pyenvWinDir = Join-Path $pyenvRoot 'pyenv-win'
    Add-UserPath (Join-Path $pyenvWinDir 'shims') -Front
    Add-UserPath (Join-Path $pyenvWinDir 'bin') -Front
    Set-UserEnv 'PYENV' (Join-Path $pyenvRoot 'pyenv-win\')
    Set-UserEnv 'PYENV_ROOT' (Join-Path $pyenvRoot 'pyenv-win\')
    Set-UserEnv 'PYENV_HOME' (Join-Path $pyenvRoot 'pyenv-win\')

    try {
        # 버전 목록 캐시를 먼저 갱신하지 않으면 latest가 오래된 값을 알려 줍니다.
        & $pyenvBat update 2>&1 | Out-Null

        # 맥은 `pyenv install -l`을 직접 훑어야 했지만, 윈도우판에는 latest 명령이 있습니다.
        $latestPy = ''
        $latestPyRaw = & $pyenvBat latest -k 3 2>$null
        if ($latestPyRaw) { $latestPy = ([string]($latestPyRaw | Select-Object -Last 1)).Trim() }

        if ([string]::IsNullOrWhiteSpace($latestPy)) {
            Write-Warn "설치할 Python 버전을 알아내지 못했습니다 → 건너뜀 (수동 설치: pyenv update; pyenv install <버전>; pyenv global <버전>)"
        }
        else {
            $pyVersions = @()
            $pyVersionsRaw = & $pyenvBat versions --bare 2>$null
            if ($pyVersionsRaw) { $pyVersions = @($pyVersionsRaw | ForEach-Object { ([string]$_).Trim() }) }

            if ($pyVersions -contains $latestPy) {
                Write-Ok "Python $latestPy 이미 설치됨"
            }
            else {
                # -q(조용히): 일부 배포판에서 설치 마법사 창이 뜨는 걸 막아 줍니다.
                & $pyenvBat install $latestPy -q
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Python $latestPy 설치 실패 → 건너뜀 (수동 설치: pyenv install $latestPy)"
                }
                else {
                    Write-Ok "Python $latestPy 설치 완료"
                }
            }

            & $pyenvBat global $latestPy 2>&1 | Out-Null
            & $pyenvBat rehash 2>&1 | Out-Null
            Write-Ok "Python 기본 버전 지정: $latestPy (새 터미널부터 python 명령에 적용)"
            Write-Info "python을 쳤는데 Microsoft Store가 열린다면: 시작 > '앱 실행 별칭 관리'에서 python·python3를 끄세요 (윈도우 기본 기능이라 스크립트가 대신 못 끕니다)"
        }
    }
    catch {
        Write-Warn "Python 설치 단계에서 문제가 생겨 건너뜁니다 (수동 설치: pyenv update; pyenv install <버전>; pyenv global <버전>)"
    }
}

# ── 6. Node.js (nvm-windows) ───────────────────────────────────
#   ★맥과 가장 크게 다른 부분입니다.
#   nvm-windows는 '심볼릭 링크'를 만드는 방식이라 관리자 권한이 필요합니다(맥은 불필요).
#   대신 한 번 `nvm use`를 해 두면 재부팅해도, 이미 열린 창에도 그대로 유지됩니다 —
#   그래서 맥처럼 프로필에 nvm 관련 줄을 넣으면 안 됩니다.
Write-Step "6. Node.js LTS 설치 (nvm-windows, npm 포함)"

$nodeBefore = Get-Command node -ErrorAction SilentlyContinue

if (-not (Test-Admin)) {
    Write-Warn "nvm-windows는 관리자 권한이 필요해 건너뜁니다 (수동 설치: 시작 메뉴에서 'Windows Terminal'을 오른쪽 클릭 > '관리자 권한으로 실행' 후 winget install --id CoreyButler.NVMforWindows -e → nvm install lts → nvm use lts)"
    Write-Info "관리자 권한 없이 쓰고 싶다면 대안으로 fnm이 있습니다: winget install --id Schniz.fnm -e (팀 표준은 nvm-windows입니다)"
}
else {
    $nvmReady = $false
    if (Test-Cmd 'nvm') {
        Write-Ok "nvm-windows 이미 설치됨"
        $nvmReady = $true
    }
    else {
        $nvmReady = Install-Winget -Id 'CoreyButler.NVMforWindows' -Name 'nvm-windows (Node 버전 관리)' -ProbeCmd 'nvm'
    }

    # 설치 직후에는 지금 창의 PATH에 nvm이 없을 수 있어 실제 파일 위치를 직접 찾습니다.
    $nvmExe = $null
    $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
    if ($nvmCmd) { $nvmExe = $nvmCmd.Source }
    if (-not $nvmExe) {
        $nvmCandidates = @(
            (Join-Path $env:APPDATA 'nvm\nvm.exe'),
            (Join-Path $env:ProgramData 'nvm\nvm.exe'),
            (Join-Path $env:ProgramFiles 'nvm\nvm.exe')
        )
        if ($env:NVM_HOME) { $nvmCandidates = @((Join-Path $env:NVM_HOME 'nvm.exe')) + $nvmCandidates }
        $nvmExe = $nvmCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }

    if (-not $nvmReady -or -not $nvmExe) {
        Write-Warn "nvm-windows를 찾지 못해 Node.js 설치를 건너뜁니다 (수동 설치: winget install --id CoreyButler.NVMforWindows -e 후 새 관리자 터미널에서 nvm install lts)"
    }
    else {
        # nvm이 관리하지 않는 기존 Node가 있으면 PATH가 충돌해 'nvm use'가 무시된 것처럼 보입니다.
        if ($nodeBefore -and -not $env:NVM_HOME) {
            Write-Info "기존 Node.js가 이미 설치돼 있습니다 ($($nodeBefore.Source)) — 버전이 안 바뀌면 제어판에서 그 Node.js를 먼저 제거하세요"
        }

        try {
            $nvmCurrent = ''
            $nvmCurrentRaw = & $nvmExe current 2>$null
            if ($nvmCurrentRaw) { $nvmCurrent = ([string]($nvmCurrentRaw | Select-Object -Last 1)).Trim() }

            if ($nvmCurrent -and $nvmCurrent -notmatch 'none|No current') {
                Write-Ok "Node.js 이미 사용 중: $nvmCurrent"
            }
            else {
                # ★문법 주의: 윈도우판은 `nvm install --lts`가 아니라 `nvm install lts` 입니다.
                & $nvmExe install lts
                & $nvmExe use lts
                $nvmAfter = ''
                $nvmAfterRaw = & $nvmExe current 2>$null
                if ($nvmAfterRaw) { $nvmAfter = ([string]($nvmAfterRaw | Select-Object -Last 1)).Trim() }
                if ($nvmAfter -and $nvmAfter -notmatch 'none|No current') {
                    Write-Ok "Node.js LTS 설치 완료: $nvmAfter (npm 포함 · 재부팅해도 유지됩니다)"
                }
                else {
                    Write-Warn "Node.js LTS 설치를 확인하지 못했습니다 → 건너뜀 (수동 설치: 관리자 터미널에서 nvm install lts; nvm use lts)"
                }
            }
            Write-Info "맥과 달리 'nvm alias default'는 없습니다 — nvm use 한 번이면 모든 창·재부팅에 계속 적용됩니다"
            # nvm 이 만드는 'C:\Program Files\nodejs' 링크는 '머신 PATH'에 있어서, 이미 열려 있는 이 창에는 아직 없습니다.
            # 바로 뒤 상태줄 단계에서 npx 를 찾을 수 있도록 지금 PATH 를 다시 읽어 들입니다.
            Update-CliToolPath
        }
        catch {
            Write-Warn "Node.js 설치 단계에서 문제가 생겨 건너뜁니다 (수동 설치: 관리자 터미널에서 nvm install lts; nvm use lts)"
        }
    }
}

# ── 6.5 Claude Code 상태줄(statusline) ──────────────────────────
#   Claude Code 화면 아래에 모델·비용·컨텍스트 사용량·git 상태를 보여 주는 줄입니다.
#   1차 ccstatusline: 대화형 화면이라 자동 등록이 거의 안 됩니다(그래도 무해하게 한 번 시도).
#   2차 Awesome CC Statusline: 공식 install.ps1에 크기(small)를 인자로 넘기면 완전 자동입니다.
#   ※ 둘 다 Node가 있어야 편하므로 Node 설치 바로 뒤에 둡니다.
Write-Step "6.5. Claude Code 상태줄 확인 (ccstatusline 시도 → 실패 시 Awesome CC Statusline(small)로 자동 대체)"

$CocodeClaudeSettings = Join-Path $env:USERPROFILE '.claude\settings.json'

function Test-CocodeStatusLine {
    if (-not (Test-Path -LiteralPath $CocodeClaudeSettings)) { return $false }
    try { return [bool](Select-String -LiteralPath $CocodeClaudeSettings -Pattern 'statusLine' -Quiet -ErrorAction SilentlyContinue) }
    catch { return $false }
}

if (Test-CocodeStatusLine) {
    Write-Ok "상태줄 이미 등록됨 ($CocodeClaudeSettings)"
}
else {
    if (Test-Cmd 'npx') {
        # "< NUL": 대화형 질문이 떠도 스크립트가 멈추지 않게 입력을 막습니다 (맥의 </dev/null 대응)
        try { cmd /c "npx -y ccstatusline@latest < NUL > NUL 2>&1" } catch { }
    }

    if (Test-CocodeStatusLine) {
        Write-Ok "상태줄 등록 완료 (ccstatusline — Claude Code에서 바로 적용)"
    }
    else {
        Write-Info "ccstatusline은 대화형 화면이라 자동 등록되지 않음 → Awesome CC Statusline(small)로 자동 설치 시도"
        try {
            $csInstaller = Join-Path $env:TEMP 'cc-statusline-install.ps1'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/AwesomeJun/CC-statusline/main/install.ps1' -OutFile $csInstaller -ErrorAction Stop
            Unblock-File -LiteralPath $csInstaller -ErrorAction SilentlyContinue
            # 크기(small)를 인자로 넘겨야 묻지 않고 끝까지 자동으로 진행됩니다.
            & $csInstaller small
        }
        catch {
            Write-Warn "상태줄 자동 등록 실패 → 건너뜀 (수동 설정: npx -y ccstatusline@latest)"
        }

        if (Test-CocodeStatusLine) {
            Write-Ok "상태줄 등록 완료 (Awesome CC Statusline, 크기: small — $CocodeClaudeSettings)"
        }
        else {
            Write-Warn "상태줄이 아직 등록되지 않았습니다 → 건너뜀 (수동 설정: npx -y ccstatusline@latest)"
        }
    }
    Write-Info "상태줄 아이콘이 □로 보이면 폰트가 터미널에 적용되지 않은 것입니다 (7.5단계=폰트 설치 · 7.5-a단계=Windows Terminal 적용 — 두 배너를 확인하세요) · 줄이 접히면 `$env:CCSTATUSLINE_WIDTH='160' 을 설정하세요"
}

# ============================================================
# 6.6. OpenCode CLI + OpenCode·Claude Code 기본 MCP
#   기본 10개: cob, dart, figma, marionette, atlassian, mobbin, slack, zenhub,
#              chrome-devtools, playwright
#   로컬 실행 파일은 4단계(Dart)·6단계(Node)에서 준비합니다. Figma·Mobbin은 OAuth,
#   Atlassian·Slack·ZenHub는 8.5단계의 팀 공용 토큰으로 인증합니다.
#   npx와 dart는 Windows 배치 파일이므로 cmd /c로 감싸 두 클라이언트에 등록합니다.
#   실제 토큰 대신 환경변수 참조를 저장하고, 기존 설정은 백업 후 병합합니다.
# ============================================================
Write-Step "6.6. OpenCode CLI 설치 + 기본 MCP 10개 등록 (OpenCode·Claude Code)"
if (Test-Cmd 'opencode') {
    Write-Ok "opencode 이미 설치됨"
} elseif (Test-Cmd 'npm') {
    try {
        & npm install -g opencode-ai
        if ($LASTEXITCODE -ne 0) { Write-Warn "OpenCode 설치 실패 → 건너뜀 (수동: npm install -g opencode-ai)" }
        Add-UserPath (Join-Path $env:APPDATA 'npm')
    } catch { Write-Warn "OpenCode 설치 실패 → 건너뜀 (수동: npm install -g opencode-ai)" }
} else {
    Write-Warn "npm 없음 → OpenCode 설치 건너뜀 (6단계 확인 후 재실행)"
}

# 작은따옴표 here-string: ${VAR}를 지금 확장하지 않고 글자 그대로 저장합니다.
$McpDefaults = @'
{
  "cob": {"type":"stdio","command":"cmd","args":["/c","dart","pub","global","run","cob:cob_mcp"]},
  "dart": {"type":"stdio","command":"cmd","args":["/c","dart","mcp-server"]},
  "figma": {"type":"http","url":"https://mcp.figma.com/mcp"},
  "marionette": {"type":"stdio","command":"cmd","args":["/c","dart","pub","global","run","marionette_mcp:marionette_mcp"]},
  "atlassian": {"type":"stdio","command":"docker","args":["run","--rm","-i","-e","JIRA_URL","-e","JIRA_USERNAME","-e","JIRA_API_TOKEN","ghcr.io/sooperset/mcp-atlassian:latest","--transport","stdio"],"env":{"JIRA_URL":"https://laputa.atlassian.net","JIRA_USERNAME":"dev@cocode.im","JIRA_API_TOKEN":"${JIRA_API_TOKEN}"}},
  "mobbin": {"type":"http","url":"https://api.mobbin.com/mcp"},
  "slack": {"type":"stdio","command":"cmd","args":["/c","npx","-y","@modelcontextprotocol/server-slack"],"env":{"SLACK_TEAM_ID":"${SLACK_TEAM_ID}","SLACK_BOT_TOKEN":"${SLACK_BOT_TOKEN}"}},
  "zenhub": {"type":"http","url":"https://api.zenhub.com/mcp","headers":{"Authorization":"${ZENHUB_API_TOKEN}","X-zh-workspace":"69ae742925c359000f5acf14"}},
  "chrome-devtools": {"type":"stdio","command":"cmd","args":["/c","npx","-y","chrome-devtools-mcp@latest"]},
  "playwright": {"type":"stdio","command":"cmd","args":["/c","npx","-y","@playwright/mcp@latest","--browser","chrome"]}
}
'@ | ConvertFrom-Json
$OpenCodeConfigRoot = Join-Path $env:USERPROFILE '.config'
if ($env:XDG_CONFIG_HOME) { $OpenCodeConfigRoot = $env:XDG_CONFIG_HOME }
$OpenCodeConfigPath = Join-Path $OpenCodeConfigRoot 'opencode\opencode.json'
foreach ($mcpClient in @('claude', 'opencode')) {
    $mcpTmp = $null
    try {
        $mcpKey = 'mcpServers'
        $mcpConfig = Join-Path $env:USERPROFILE '.claude.json'
        if ($mcpClient -eq 'opencode') { $mcpKey = 'mcp'; $mcpConfig = $OpenCodeConfigPath }
        $cfg = New-Object PSObject
        if (Test-Path -LiteralPath $mcpConfig) {
            $cfg = [IO.File]::ReadAllText($mcpConfig) | ConvertFrom-Json -ErrorAction Stop
            if ($cfg -isnot [PSCustomObject] -or ($null -ne $cfg.$mcpKey -and $cfg.$mcpKey -isnot [PSCustomObject])) {
                Write-Warn "$mcpConfig 형식 확인 필요 → 원본을 유지합니다"
                continue
            }
            if (-not (Test-Path -LiteralPath "$mcpConfig.bak")) {
                Copy-Item -LiteralPath $mcpConfig -Destination "$mcpConfig.bak" -ErrorAction Stop
            }
        }
        if ($null -eq $cfg.$mcpKey) {
            $cfg | Add-Member -NotePropertyName $mcpKey -NotePropertyValue (New-Object PSObject) -Force
        }
        foreach ($server in $McpDefaults.PSObject.Properties) {
            $entry = $server.Value
            if ($mcpClient -eq 'opencode') {
                if ($entry.type -eq 'http') {
                    $converted = [ordered]@{ type = 'remote'; url = $entry.url; enabled = $true }
                    if ($entry.headers) {
                        $headers = @{}
                        foreach ($prop in $entry.headers.PSObject.Properties) {
                            $headers[$prop.Name] = ([string]$prop.Value) -replace '\$\{([A-Z_]+)\}', '{env:$1}'
                        }
                        $converted['oauth'] = $false
                        $converted['headers'] = $headers
                    }
                } else {
                    $converted = [ordered]@{ type = 'local'; command = @($entry.command) + @($entry.args); enabled = $true; timeout = 30000 }
                    if ($entry.env) {
                        $environment = @{}
                        foreach ($prop in $entry.env.PSObject.Properties) {
                            $environment[$prop.Name] = ([string]$prop.Value) -replace '\$\{([A-Z_]+)\}', '{env:$1}'
                        }
                        $converted['environment'] = $environment
                    }
                }
                $entry = [PSCustomObject]$converted
            }
            $cfg.$mcpKey | Add-Member -NotePropertyName $server.Name -NotePropertyValue $entry -Force
        }
        # 예전 팀 Docker 등록명만 atlassian으로 통합합니다. 다른 사용자 MCP는 유지합니다.
        $legacy = $cfg.$mcpKey.'mcp-atlassian'
        if ($legacy.command -eq 'docker' -and $legacy.args -contains 'ghcr.io/sooperset/mcp-atlassian:latest') {
            $cfg.$mcpKey.PSObject.Properties.Remove('mcp-atlassian')
        }
        if ($mcpClient -eq 'opencode') {
            $cfg | Add-Member -NotePropertyName '$schema' -NotePropertyValue 'https://opencode.ai/config.json' -Force
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $mcpConfig) -Force -ErrorAction Stop | Out-Null
        $mcpTmp = "$mcpConfig.tmp.$([Guid]::NewGuid().ToString('N'))"
        [IO.File]::WriteAllText($mcpTmp, ($cfg | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $mcpTmp -Destination $mcpConfig -Force -ErrorAction Stop
        Write-Ok "$mcpClient 기본 MCP 10개 등록/갱신 (기존 설정 병합)"
    } catch {
        if ($mcpTmp -and (Test-Path -LiteralPath $mcpTmp)) { Remove-Item -LiteralPath $mcpTmp -Force -ErrorAction SilentlyContinue }
        Write-Warn "$mcpClient MCP 설정 저장 실패 → 원본을 유지합니다 (JSON 주석·문법 확인 후 재실행)"
    }
}
if (Test-Path -LiteralPath ($OpenCodeConfigPath + 'c')) {
    Write-Info "기존 opencode.jsonc의 같은 이름 설정이 우선 적용됩니다 — opencode mcp list 로 확인하세요"
}
Write-Info "새 PowerShell 창에서 두 도구를 재시작하세요. Claude Code: /mcp · OpenCode: opencode mcp auth figma · opencode mcp auth mobbin"

# ============================================================
# 7. PowerShell 프로필 · PSReadLine
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   맥에서는 터미널을 열 때마다 ~/.zshrc 라는 설정 파일이 자동으로 읽힙니다.
#   윈도우 PowerShell에서 그 역할을 하는 파일이 "프로필(Profile.ps1)"입니다.
#   여기에 팀 공용 설정(자동 제안·구문 색상·한글 인코딩)을 넣어 둡니다.
#
#   [맥과 다른 점 — 꼭 알아두세요]
#   · oh-my-zsh 같은 프레임워크를 쓰지 않습니다. PowerShell은 프로필 파일 한 장 +
#     Oh My Posh(프롬프트) + PSReadLine(자동 제안·색상) 조합으로 같은 효과를 냅니다.
#   · 프로필 경로를 직접 적지 않고 항상 $PROFILE 변수에서 읽습니다. 윈도우의 '문서'
#     폴더는 OneDrive 백업 때문에 사람마다 실제 위치가 다르기 때문입니다.
#   · 그래서 토큰(비밀값)은 프로필에 절대 넣지 않습니다(8.5단계에서 따로 처리).
#     프로필이 OneDrive로 동기화되면 비밀값이 클라우드로 올라가 버립니다.
# ------------------------------------------------------------
Write-Step "7. PowerShell 프로필 설정 (맥의 ~/.zshrc 자리 — 자동 제안·구문 색상·한글 인코딩)"

# ── 7-a 실행 정책 ──────────────────────────────────────────────
#   윈도우는 기본값(Restricted)에서 .ps1 파일 실행을 막습니다. 이 상태면 프로필이
#   "조용히" 안 읽혀서 프롬프트도 자동 제안도 전부 먹통이 됩니다(에러조차 안 납니다).
#   그래서 내 계정(CurrentUser) 범위만 RemoteSigned로 풀어 줍니다.
#   ※ LocalMachine(PC 전체) 범위는 쓰지 않습니다 — 관리자 권한이 필요한 데다,
#     스토어(MSIX) 방식으로 설치된 PowerShell 7에서는 아예 막혀 있습니다.
try {
    $currentPolicy = [string](Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop)
    if (@('RemoteSigned', 'Unrestricted', 'Bypass') -contains $currentPolicy) {
        Write-Ok "PowerShell 실행 정책 이미 허용됨 (내 계정 = $currentPolicy)"
    }
    else {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        Write-Ok "PowerShell 실행 정책을 RemoteSigned로 설정 (내 계정 범위만)"
    }
}
catch {
    Write-Warn "실행 정책 설정 실패 → 건너뜀 (수동 설정: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser)"
}

# ── 7-b 프로필 파일 준비 ────────────────────────────────────────
#   CurrentUserAllHosts(Profile.ps1)를 씁니다. VS Code 통합 터미널은 별도 프로필을
#   쓰기 때문에, AllHosts에 넣어야 어디서 터미널을 열든 똑같이 적용됩니다.
#   (맥의 ~/.zshrc가 모든 zsh 세션에 적용되는 것과 같은 의미)
$CocodeProfilePath = $null
try { $CocodeProfilePath = $PROFILE.CurrentUserAllHosts } catch { $CocodeProfilePath = $null }
if ([string]::IsNullOrWhiteSpace($CocodeProfilePath)) {
    $CocodeProfilePath = Join-Path $HOME 'Documents\PowerShell\Profile.ps1'
    Write-Warn "프로필 경로를 자동으로 알아내지 못해 기본값을 사용합니다: $CocodeProfilePath"
}

try {
    $profileDir = Split-Path -Parent $CocodeProfilePath
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force -ErrorAction Stop | Out-Null
    }

    if (-not (Test-Path -LiteralPath $CocodeProfilePath)) {
        # 머리말 안내대로 '기존 PC의 Profile.ps1 을 이 스크립트와 같은 폴더에 복사해 둔' 경우,
        # 그 파일을 새 프로필의 출발점으로 삼습니다. (프로필이 이미 있는 PC 는 이 갈래로 오지 않으므로 덮어쓸 일이 없습니다)
        $seedProfile = $null
        if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
            $seedCandidate = Join-Path $ScriptDir 'Profile.ps1'
            if (Test-Path -LiteralPath $seedCandidate) { $seedProfile = $seedCandidate }
        }
        if ($seedProfile) {
            Copy-Item -LiteralPath $seedProfile -Destination $CocodeProfilePath -Force -ErrorAction Stop
        }
        else {
            New-Item -ItemType File -Path $CocodeProfilePath -Force -ErrorAction Stop | Out-Null
        }
        if ($seedProfile) {
            Write-Ok "프로필 파일 생성: $CocodeProfilePath (스크립트 옆에 둔 Profile.ps1 을 출발점으로 복사했습니다)"
            Write-Info "↳ 가져온 원본: $seedProfile · 팀 공용 설정은 이 파일 끝에 co:code 블록으로 덧붙여집니다"
        }
        else {
            Write-Ok "프로필 파일 생성: $CocodeProfilePath (빈 파일에서 시작)"
            Write-Info "↳ 기존 PC 설정을 옮기려면 그 PC 의 Profile.ps1 을 이 스크립트와 같은 폴더에 복사한 뒤 다시 실행하세요"
        }
    }
    else {
        # 원본 백업은 "처음 한 번만" 만듭니다 — 열 번 실행해도 .bak 파일이 쌓이지 않게.
        $profileLeaf = Split-Path -Leaf $CocodeProfilePath
        $oldBackups = @(Get-ChildItem -LiteralPath $profileDir -Filter "$profileLeaf.bak-*" -ErrorAction SilentlyContinue)
        if ($oldBackups.Count -eq 0) {
            $profileBak = "$CocodeProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $CocodeProfilePath -Destination $profileBak -Force -ErrorAction SilentlyContinue
            Write-Ok "프로필 파일 확인: $CocodeProfilePath (원본 백업: $(Split-Path -Leaf $profileBak))"
        }
        else {
            Write-Ok "프로필 파일 확인: $CocodeProfilePath"
        }
    }
}
catch {
    Write-Warn "프로필 파일을 만들지 못했습니다 → 프로필 설정 건너뜀 (수동: New-Item -ItemType File -Path `$PROFILE.CurrentUserAllHosts -Force)"
    $CocodeProfilePath = $null
}

# OneDrive 리디렉션은 막지 않고 알려만 줍니다(해제 여부는 본인 판단).
if ($CocodeProfilePath -and $CocodeProfilePath -like '*OneDrive*') {
    Write-Info "프로필이 OneDrive 폴더 안에 있습니다: $CocodeProfilePath"
    Write-Info "↳ 동기화 중에는 프로필이 늦게 읽히거나 실패할 수 있습니다 (비밀값은 프로필에 넣지 않으니 유출 위험은 없습니다)"
}

# ── 7-c 프로필 블록 기록 헬퍼 (이 스크립트 전용) ───────────────────
#   같은 이름의 블록이 이미 있으면 통째로 걷어내고 파일 끝에 다시 씁니다.
#   덕분에 열 번을 실행해도 같은 줄이 쌓이지 않습니다(멱등).
#   사용자가 직접 적은 개인 설정은 블록 밖에 있으므로 절대 건드리지 않습니다.
function Set-CocodeProfileBlock {
    param(
        [string]$Path,
        [string]$Name,
        [string[]]$Lines
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $beginMark = "# ===== co:code $Name 시작 (win-setup.ps1이 관리 — 직접 고치면 다음 실행 때 덮어써집니다) ====="
    $endMark = "# ===== co:code $Name 끝 ====="

    try {
        $existing = @()
        if (Test-Path -LiteralPath $Path) {
            $existing = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
            # 파일에 내용이 있는데 한 줄도 못 읽었다면(잠김 등) 통째로 덮어쓰는 사고를 막고 중단합니다.
            $fileLen = (Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue).Length
            if ($existing.Count -eq 0 -and $fileLen -gt 0) {
                Write-Warn "프로필 파일을 읽지 못해 '$Name' 블록 기록을 건너뜁니다 (다른 프로그램이 파일을 잡고 있을 수 있습니다)"
                return $false
            }
        }

        $kept = New-Object 'System.Collections.Generic.List[string]'
        $inBlock = $false
        foreach ($line in $existing) {
            if ($line -eq $beginMark) { $inBlock = $true; continue }
            if ($inBlock) {
                if ($line -eq $endMark) { $inBlock = $false }
                continue
            }
            $kept.Add($line)
        }

        # 블록을 걷어낸 자리에 남은 빈 줄 정리 → 재실행해도 파일이 길어지지 않습니다.
        while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
            $kept.RemoveAt($kept.Count - 1)
        }
        if ($kept.Count -gt 0) { $kept.Add('') }

        $kept.Add($beginMark)
        foreach ($l in $Lines) { $kept.Add($l) }
        $kept.Add($endMark)

        # utf8BOM: 한글 주석이 들어가므로 BOM을 붙여야 옛 PowerShell(5.1)에서도 안 깨집니다.
        # ※ 윈도우 PowerShell 5.1 의 Set-Content 에는 utf8BOM 값이 없어 파라미터 오류가 납니다
        #    → 두 버전 모두에서 되는 .NET 방식으로 직접 씁니다.
        [IO.File]::WriteAllLines($Path, [string[]]$kept.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
        return $true
    }
    catch {
        Write-Warn "프로필에 '$Name' 블록을 쓰지 못했습니다 → 건너뜀 (수동: notepad `$PROFILE.CurrentUserAllHosts)"
        return $false
    }
}

# ── 7-d PSReadLine 최신화 ──────────────────────────────────────
#   PSReadLine은 "예전에 친 명령을 회색으로 미리 보여주는" 기능(맥의 zsh-autosuggestions)을
#   담당합니다. 이 기능은 2.2.0 이상에서만 되는데 PowerShell 7에는 이미 훨씬 최신 버전이
#   들어 있어 대부분 아무것도 안 해도 됩니다. 혹시 낮으면 내 계정 범위로만 갱신합니다.
try {
    $psrl = Get-Module PSReadLine -ListAvailable -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($psrl -and $psrl.Version -ge [version]'2.2.0') {
        Write-Ok "PSReadLine $($psrl.Version) 이미 설치됨 (자동 제안·구문 색상 지원 버전)"
    }
    else {
        Write-Info "PSReadLine 버전이 낮아 갱신합니다 (자동 제안 기능에 2.2.0 이상이 필요)"
        Install-Module -Name PSReadLine -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        Write-Ok "PSReadLine 갱신 완료"
    }
}
catch {
    Write-Warn "PSReadLine 갱신 실패 → 건너뜀 (수동 설치: Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber)"
}

# ── 7-e 팀 공용 설정 블록 기록 ──────────────────────────────────
$cocodeProfileLines = @(
    '# co:code 팀 표준 PowerShell 설정입니다.',
    '# 개인 설정은 이 블록 "바깥"(위쪽)에 적어 주세요 — 블록 안은 다음 실행 때 덮어써집니다.',
    '#',
    '# 참고: Python(pyenv-win)·Node(nvm-windows) 경로는 여기가 아니라 윈도우 사용자 PATH에',
    '#       등록돼 있습니다. 맥과 달리 프로필에 관련 줄을 넣으면 오히려 충돌합니다.',
    '',
    '# 한글·이모지가 깨지지 않도록 출력 인코딩을 UTF-8로 고정',
    'try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }',
    '',
    '# PSReadLine — 맥의 zsh-autosuggestions(회색 자동 제안) + zsh-syntax-highlighting(구문 색상) 대체',
    '#   PredictionSource History   : 예전에 친 명령을 회색으로 미리 보여준다 (→ 또는 End 키로 수락)',
    '#   PredictionViewStyle Inline : zsh와 똑같은 "한 줄 회색 제안" 방식 (목록으로 보고 싶으면 ListView)',
    '#   ※ 구문 색상은 PSReadLine이 기본 제공합니다. 다만 zsh처럼 "없는 명령을 빨갛게"는 표시하지 않습니다.',
    'if (Get-Module -Name PSReadLine) {',
    '    try {',
    '        Set-PSReadLineOption -EditMode Windows',
    '        Set-PSReadLineOption -PredictionSource History',
    '        Set-PSReadLineOption -PredictionViewStyle InlineView',
    '        Set-PSReadLineOption -Colors @{',
    '            Command   = ''Magenta''',
    '            Parameter = ''DarkGray''',
    '            String    = ''DarkGreen''',
    '            Operator  = ''DarkGray''',
    '            Variable  = ''DarkGreen''',
    '            Number    = ''DarkGray''',
    '            Type      = ''DarkGray''',
    '            Comment   = ''DarkGray''',
    '        }',
    '    }',
    '    catch { }',
    '}',
    '',
    '# 팀 작업 폴더로 한 번에 이동 (맥 .zshrc의 alias cocode 대응)',
    'function cocode {',
    '    $dir = Join-Path $HOME ''Development\cocode''',
    '    if (Test-Path -LiteralPath $dir) { Set-Location -LiteralPath $dir }',
    '    else { Write-Host "  · $dir 폴더가 아직 없습니다" -ForegroundColor DarkGray }',
    '}'
)

if (Set-CocodeProfileBlock -Path $CocodeProfilePath -Name '공용 설정' -Lines $cocodeProfileLines) {
    Write-Ok "프로필에 팀 공용 설정 반영 완료 (자동 제안·구문 색상·UTF-8·cocode 이동 함수)"
    Write-Info "지금 이 창에는 아직 적용되지 않습니다 — 새 터미널을 열면 보입니다"
}

# ============================================================
# 7.3. Oh My Posh (프롬프트 테마 — 맥의 powerlevel10k 자리)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   터미널에 뜨는 "현재 폴더 / git 브랜치 / 실행 시간" 같은 예쁜 프롬프트를 켭니다.
#   맥에서 쓰던 powerlevel10k는 zsh 전용이라 윈도우에서는 못 씁니다. 대신 Oh My Posh가
#   powerlevel10k를 그대로 옮겨 온 공식 테마(powerlevel10k_rainbow)를 제공합니다.
#
#   [주의] 요즘 Oh My Posh는 MSIX(스토어 앱) 방식으로 설치돼서, 예전 블로그에 나오는
#   테마 폴더($env:POSH_THEMES_PATH)가 존재하지 않습니다. 그래서 테마는 폴더 경로가 아니라
#   "이름"으로 지정합니다 — 지금 버전에서 유일하게 안정적인 방법입니다.
# ------------------------------------------------------------
Write-Step "7.3. Oh My Posh 설치 + 프롬프트 테마 적용 (맥 powerlevel10k 대체, 테마: powerlevel10k_rainbow)"

$CocodeOmpTheme = 'powerlevel10k_rainbow'
$ompReady = $false

if (Test-Cmd 'oh-my-posh') {
    Write-Ok "Oh My Posh 이미 설치됨"
    $ompReady = $true
}
else {
    $ompReady = Install-Winget -Id 'JanDeDobbeleer.OhMyPosh' -Name 'Oh My Posh (프롬프트 테마)' -ProbeCmd 'oh-my-posh' -Scope user
    if (-not $ompReady) {
        # winget이 없거나 실패하면 공식 설치 스크립트로 한 번 더 시도합니다.
        # (관리자 권한 없이 현재 사용자에게만 설치됩니다)
        Write-Info "winget 설치가 안 돼서 공식 설치 스크립트로 다시 시도합니다"
        try {
            $ompInstaller = Join-Path $env:TEMP 'install-oh-my-posh.ps1'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://ohmyposh.dev/install.ps1' -OutFile $ompInstaller -ErrorAction Stop
            Unblock-File -LiteralPath $ompInstaller -ErrorAction SilentlyContinue
            & $ompInstaller
            $ompReady = $true
            Write-Ok "Oh My Posh 설치 완료 (공식 설치 스크립트)"
        }
        catch {
            Write-Warn "Oh My Posh 설치 실패 → 건너뜀 (수동 설치: winget install --id JanDeDobbeleer.OhMyPosh -e --source winget)"
        }
    }
}

# 설치 직후에는 지금 창의 PATH에 아직 안 잡히는 경우가 있어, 흔한 설치 폴더를 PATH에 넣어 둡니다.
$ompBinDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin'
if (Test-Path -LiteralPath $ompBinDir) { Add-UserPath $ompBinDir }

# 프롬프트 초기화 한 줄은 프로필 "맨 끝"에 있어야 합니다 — 다른 설정이 프롬프트를 덮어쓰지 않도록.
# (5단계 공용 블록 → 6단계 프롬프트 블록 순서로 기록되므로 항상 맨 끝에 옵니다)
$ompProfileLines = @(
    '# Oh My Posh 프롬프트 (맥 powerlevel10k 대체)',
    '#   테마를 바꾸려면 아래 따옴표 안 이름만 바꾸세요.',
    '#   목록 보기: oh-my-posh config list  ·  비슷한 계열: powerlevel10k_lean / powerlevel10k_classic / powerlevel10k_modern',
    'if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {',
    "    try { oh-my-posh init pwsh --config '$CocodeOmpTheme' | Invoke-Expression } catch { }",
    '}'
)

if (Set-CocodeProfileBlock -Path $CocodeProfilePath -Name '프롬프트 테마' -Lines $ompProfileLines) {
    Write-Ok "프로필에 프롬프트 테마 적용 ($CocodeOmpTheme — 새 터미널부터 보입니다)"
}

# ============================================================
# 7.5. 폰트 (MesloLGS NF) + Windows Terminal 자동 적용
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   위에서 켠 프롬프트는 아이콘(폴더·git 브랜치 모양)을 글자처럼 그립니다. 그 아이콘이
#   들어 있는 특수 폰트가 없으면 전부 네모(□)로 깨져 보입니다. 그래서 폰트를 설치하고,
#   Windows Terminal이 실제로 그 폰트를 쓰도록 설정까지 대신 해 줍니다.
#
#   [왜 이 폰트인가]
#   맥 스크립트와 완전히 같은 'MesloLGS NF'를 씁니다. `oh-my-posh font install meslo`도
#   있지만 그건 폰트 이름이 'MesloLGS Nerd Font'로 달라서, 맥과 같은 설정값을 넣으면 폰트를
#   못 찾고 조용히 기본 폰트로 되돌아갑니다(에러도 안 납니다). 게다가 116MB·72개를 받습니다.
#   여기서는 4개 파일(약 7MB)만 받아 내 계정 폰트로 설치합니다 — 관리자 권한 불필요.
# ------------------------------------------------------------
Write-Step "7.5. MesloLGS NF 폰트 설치 (프롬프트 아이콘이 □로 깨지지 않게 — 맥과 같은 폰트)"

$CocodeFontFace = 'MesloLGS NF'
$fontFiles = @(
    'MesloLGS NF Regular.ttf',
    'MesloLGS NF Bold.ttf',
    'MesloLGS NF Italic.ttf',
    'MesloLGS NF Bold Italic.ttf'
)
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$fontRegKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$installedFontPaths = @()

try {
    if (-not (Test-Path -LiteralPath $fontDir)) {
        New-Item -ItemType Directory -Path $fontDir -Force -ErrorAction Stop | Out-Null
    }
    if (-not (Test-Path -LiteralPath $fontRegKey)) {
        New-Item -Path $fontRegKey -Force -ErrorAction Stop | Out-Null
    }

    foreach ($fontFile in $fontFiles) {
        $dst = Join-Path $fontDir $fontFile

        if (Test-Path -LiteralPath $dst) {
            Write-Ok "$fontFile 이미 설치됨"
        }
        else {
            $fontDownloaded = $false
            try {
                # 파일 이름에 공백이 있어 URL 인코딩(%20)이 반드시 필요합니다.
                $fontUrl = 'https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master/' + [uri]::EscapeDataString($fontFile)
                Invoke-WebRequest -UseBasicParsing -Uri $fontUrl -OutFile $dst -ErrorAction Stop
                # 받다 만 파일이나 에러 페이지가 폰트로 등록되는 사고를 막습니다.
                if ((Get-Item -LiteralPath $dst -ErrorAction Stop).Length -ge 100KB) { $fontDownloaded = $true }
                else { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
            }
            catch {
                $fontDownloaded = $false
            }

            if (-not $fontDownloaded) {
                Write-Warn "$fontFile 내려받기 실패 → 건너뜀 (수동 설치: https://github.com/romkatv/powerlevel10k/blob/master/font.md 에서 받아 파일을 두 번 클릭 후 '설치')"
                continue
            }
            Write-Ok "$fontFile 설치 완료"
        }

        # 내 계정 폰트 목록에 등록 (관리자 권한 불필요). 이름 관례는 '<표시명> (TrueType)'
        try {
            $regName = ($fontFile -replace '\.ttf$', '') + ' (TrueType)'
            New-ItemProperty -Path $fontRegKey -Name $regName -Value $dst -PropertyType String -Force -ErrorAction Stop | Out-Null
            $installedFontPaths += $dst
        }
        catch {
            Write-Warn "$fontFile 폰트 등록 실패 → 건너뜀 (파일을 두 번 클릭한 뒤 '설치' 버튼으로 직접 등록)"
        }
    }
}
catch {
    Write-Warn "폰트 설치 폴더를 준비하지 못했습니다 → 폰트 설치 건너뜀 (수동 설치: powerlevel10k font.md 안내 참고)"
}

# 지금 실행 중인 앱들도 새 폰트를 알아보도록 신호를 보냅니다 (WM_FONTCHANGE).
# 그래도 이미 열려 있던 터미널 탭은 재시작해야 확실히 반영됩니다.
if ($installedFontPaths.Count -gt 0) {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'CocodeWin.FontNotify').Type) {
            Add-Type -Namespace CocodeWin -Name FontNotify -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string lpFileName);

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction Stop
        }
        foreach ($fontPath in $installedFontPaths) { [CocodeWin.FontNotify]::AddFontResourceW($fontPath) | Out-Null }
        $fontMsgResult = [UIntPtr]::Zero
        [CocodeWin.FontNotify]::SendMessageTimeout([IntPtr]0xffff, 0x1D, [UIntPtr]::Zero, $null, 2, 5000, [ref]$fontMsgResult) | Out-Null
        Write-Info "설치한 폰트를 실행 중인 앱에 알렸습니다 (열려 있던 터미널은 껐다 켜야 확실히 반영됩니다)"
    }
    catch {
        Write-Info "폰트 알림 신호를 보내지 못했습니다 → 터미널을 껐다 켜면 반영됩니다"
    }
}

# ── 7.5-a Windows Terminal 폰트 자동 적용 ───────────────────────
#   폰트는 "설치"만으로는 부족하고, 터미널이 그 폰트를 쓰도록 골라 줘야 합니다.
#   맥에서 AppleScript로 Terminal.app 프로필 폰트를 바꾸던 단계와 같은 역할입니다.
Write-Step "7.5-a. Windows Terminal 폰트 자동 적용 ($CocodeFontFace)"

$wtSettingsCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$wtSettings = $wtSettingsCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($PSVersionTable.PSVersion.Major -lt 6) {
    # ConvertFrom-Json -AsHashtable 은 PowerShell 7 전용입니다. 5.1 에서 억지로 읽으면 설정 파일이
    # 통째로 망가질 수 있어, 자동 적용을 하지 않고 직접 고르는 방법만 알려 줍니다.
    Write-Warn "이 창은 윈도우 PowerShell 5.1 이라 Windows Terminal 폰트를 자동으로 바꾸지 못했습니다 → 건너뜀"
    Write-Info "수동 설정: Windows Terminal > 설정(Ctrl+,) > 프로필 > 기본값 > 추가 설정 > 모양 > 글꼴 에서 '$CocodeFontFace' 선택"
    Write-Info "자동으로 맞추고 싶다면 PowerShell 7 을 깔고 다시 실행하세요: winget install --id Microsoft.PowerShell -e"
}
elseif (-not $wtSettings) {
    # Windows 11에는 기본 탑재라 대부분 이미 있습니다. Windows 10이면 없을 수 있어 설치만 시도합니다.
    if (-not (Test-Cmd 'wt')) {
        Install-Winget -Id 'Microsoft.WindowsTerminal' -Name 'Windows Terminal' -ProbeCmd 'wt' -Scope user | Out-Null
    }
    Write-Warn "Windows Terminal 설정 파일이 아직 없어 폰트를 자동 적용하지 못했습니다 → 건너뜀 (Windows Terminal을 한 번 실행한 뒤 이 스크립트를 다시 실행하거나, 설정 > 기본값 > 모양 > 글꼴에서 '$CocodeFontFace' 선택)"
}
else {
    try {
        # -AsHashtable: 키 순서를 최대한 보존 / -Depth 32: 기본값(2)이면 설정이 통째로 잘려 나갑니다.
        # (설정 파일의 // 주석은 이 방식으로 저장하면 사라지므로, 바꿔 쓰기 직전에 백업을 뜹니다)
        $wtJson = Get-Content -LiteralPath $wtSettings -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (-not $wtJson.ContainsKey('profiles')) { $wtJson['profiles'] = @{} }
        if (-not $wtJson['profiles'].ContainsKey('defaults')) { $wtJson['profiles']['defaults'] = @{} }

        $wtCurrentFace = ''
        if ($wtJson['profiles']['defaults'].ContainsKey('font')) {
            if ($wtJson['profiles']['defaults']['font'].ContainsKey('face')) {
                $wtCurrentFace = [string]$wtJson['profiles']['defaults']['font']['face']
            }
        }

        if ($wtCurrentFace -eq $CocodeFontFace) {
            Write-Ok "Windows Terminal 폰트 이미 '$CocodeFontFace'로 설정됨"
        }
        else {
            # 원본 백업은 "처음 한 번만" 만듭니다 — 폰트를 도로 바꿔 쓰는 PC 에서 .bak-* 가 매번 쌓이지 않게.
            $wtDir = Split-Path -Parent $wtSettings
            $wtLeaf = Split-Path -Leaf $wtSettings
            $wtOldBaks = @(Get-ChildItem -LiteralPath $wtDir -Filter "$wtLeaf.bak-*" -ErrorAction SilentlyContinue)
            $wtBak = $null
            if ($wtOldBaks.Count -eq 0) {
                $wtBak = "$wtSettings.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
            if ($wtBak) { Copy-Item -LiteralPath $wtSettings -Destination $wtBak -Force -ErrorAction Stop }
            # font 객체를 통째로 갈아끼우면 사용자가 잡아 둔 글꼴 크기(size)·굵기(weight)가 말없이 사라집니다.
            # → 있는 객체는 그대로 두고 face 키 하나만 바꿉니다.
            if (-not $wtJson['profiles']['defaults'].ContainsKey('font')) {
                $wtJson['profiles']['defaults']['font'] = @{}
            }
            if ($wtJson['profiles']['defaults']['font'] -is [System.Collections.IDictionary]) {
                $wtJson['profiles']['defaults']['font']['face'] = $CocodeFontFace
            }
            else {
                # 옛 설정 파일은 font 가 글꼴 이름 문자열 하나일 수 있습니다 — 이때만 새 객체로 바꿉니다.
                $wtJson['profiles']['defaults']['font'] = @{ face = $CocodeFontFace }
            }
            $wtJson | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $wtSettings -Encoding utf8 -ErrorAction Stop
            if ($wtBak) {
                Write-Ok "Windows Terminal 기본 폰트를 '$CocodeFontFace'로 적용 (원본 백업: $(Split-Path -Leaf $wtBak))"
            }
            else {
                Write-Ok "Windows Terminal 기본 폰트를 '$CocodeFontFace'로 적용 (원본 백업은 처음 실행 때 이미 만들어 두었습니다)"
            }
            Write-Info "열려 있는 탭에는 바로 반영되지 않을 수 있습니다 — Windows Terminal을 껐다 켜세요"
        }
    }
    catch {
        Write-Warn "Windows Terminal 설정 파일을 읽지 못했습니다 → 폰트 수동 설정 필요 (설정 > 기본값 > 모양 > 글꼴에서 '$CocodeFontFace' 선택 · 파일: $wtSettings)"
    }
}

}


# ------------------------------------------------------------
# -EnvOnly 사전 점검
#   토큰은 윈도우 '사용자 환경변수'에 들어간다. 맥처럼 붙여 넣을 ~/.zshrc 골격이
#   필요하지 않으므로, 여기서는 op(1Password CLI) 유무만 미리 알려 준다.
# ------------------------------------------------------------
if ($EnvOnly -and (-not (Test-Cmd 'op'))) {
    Write-Warn "op(1Password CLI)가 없습니다 — 토큰을 읽어올 수 없습니다"
    Write-Info "먼저 설치해 주세요: winget install --id AgileBits.1Password.CLI --exact"
    Write-Info "설치 후 1Password 앱 > 설정 > 개발자 > '1Password CLI와 통합' 을 켜고 다시 실행하세요"
}


# ══════════════════════════════════════════════════════════════
# 8.5단계 — 팀 공용 토큰 주입 (-EnvOnly 로도 실행)
# ══════════════════════════════════════════════════════════════
if ($RunInstall -or $EnvOnly) {


# ============================================================
# 8.5 팀 공용 토큰 주입 (1Password → 윈도우 사용자 환경변수)
#
#   [이 단계가 하는 일 — 비개발자용 설명]
#   ZenHub·Jira·Slack 같은 서비스를 쓰려면 비밀번호 같은 '토큰' 값이 필요합니다.
#   이 값들은 팀 공용 1Password 금고에 들어 있고, 1Password CLI(op)가 대신 읽어옵니다.
#   읽어온 값은 윈도우 '사용자 환경변수'에 저장합니다.
#
#   [맥과 다른 점 — 왜 파일이 아니라 환경변수인가]
#   맥은 ~/.zshrc 파일에 적었지만, 윈도우에서 그에 해당하는 프로필 파일은 '문서' 폴더 안에
#   있어서 OneDrive로 자동 백업됩니다 — 즉 파일에 적으면 토큰이 클라우드로 올라갑니다.
#   사용자 환경변수에 넣으면 그럴 일이 없고, 터미널뿐 아니라 아이콘으로 실행한
#   Claude Code·VS Code·Docker Desktop에서도 값이 그대로 읽힙니다.
#
#   [한계 — 반드시 알아두세요]
#   이건 '실수로 git에 올라가는 사고'를 막아 주는 것이지 '암호화'가 아닙니다.
#   내 계정으로 실행되는 프로그램은 이 값을 그냥 읽을 수 있습니다.
# ------------------------------------------------------------

# 팀 1Password 항목 경로 (경로 자체는 비밀이 아닙니다 — 값은 1Password 안에만 있습니다)
$ZenhubTokenOpRef = 'op://API Token/ZenHub API Token/credential'
$JiraTokenOpRef = 'op://API Token/Laputa Atlassian API Token/Jira API Token'
$SlangGptTokenOpRef = 'op://API Token/Slang GPT API Token/credential'
$DcmEmailOpRef = 'op://API Token/DCM CI CD/username'
$DcmCiKeyOpRef = 'op://API Token/DCM CI CD/credential'
$SlackTeamIdOpRef = 'op://API Token/Cocode Slack/SLACK_TEAM_ID'
$SlackBotTokenOpRef = 'op://API Token/Cocode Slack/SLACK_BOT_TOKEN'
$TypesafeTokenOpRef = 'op://API Token/TypeSafe Jev/credential'
$OpenaiTokenOpRef = 'op://API Token/OPENAI_API_KEY/credential'

# 화면 안내에만 쓰는 팀 계정 이름 (비밀 아님). 스크립트 상단에 이미 있으면 그 값을 씁니다.
$opAccountLabel = 'team-cocodeinc.1password.com'
if (Get-Variable -Name 'TeamOpAccount' -ErrorAction SilentlyContinue) {
    if ($TeamOpAccount) { $opAccountLabel = $TeamOpAccount }
}

# 마지막 검증 단계에서 재사용할 op 상태: missing(미설치) / not-ready(설정 미완료) / ready(읽힘)
$OpStatus = 'missing'

# 값이 비어 있는 기존 환경변수는 먼저 지웁니다.
#   빈 값이 남아 있으면 MCP가 '연결됨'처럼 보이면서 실제 호출만 조용히 실패합니다.
function Clear-CocodeEmptySecret {
    param([string]$Name)
    try {
        $cur = [Environment]::GetEnvironmentVariable($Name, 'User')
        if ($null -ne $cur -and [string]::IsNullOrWhiteSpace($cur)) {
            [Environment]::SetEnvironmentVariable($Name, $null, 'User')
            if (Test-Path -LiteralPath "Env:$Name") { Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue }
            Write-Info "값이 비어 있던 $Name 을(를) 제거했습니다 (잘못된 인증 상태 방지)"
        }
    }
    catch { }
}

# 1Password에서 값을 읽어 사용자 환경변수에 넣습니다.
#   이름·경로를 여러 개 넘기면 '전부 읽혔을 때만' 주입합니다 — 반쪽만 채워져 인증이
#   애매해지는 걸 막기 위해서입니다(DCM·Slack처럼 두 값이 한 쌍인 경우).
function Set-CocodeTeamSecret {
    param(
        [string[]]$Names,
        [string[]]$Refs,
        [string]$Label,
        [string]$Hint,
        [switch]$Quiet
    )

    foreach ($n in $Names) { $null = Clear-CocodeEmptySecret -Name $n }

    if (-not (Test-Cmd 'op')) {
        if (-not $Quiet) {
            Write-Warn "$Label 미주입 — op(1Password CLI)가 없습니다 → 건너뜀 (수동 설치: winget install --id AgileBits.1Password.CLI -e --source winget 후 .\win-setup.ps1 -EnvOnly)"
        }
        return $false
    }

    $values = @()
    foreach ($ref in $Refs) {
        $val = $null
        try { $val = Get-OpSecret $ref } catch { $val = $null }
        # op 출력 끝에 줄바꿈이 붙을 수 있어 반드시 다듬습니다.
        if ($val) { $val = ([string]$val).Trim() }
        if ([string]::IsNullOrWhiteSpace($val)) {
            if (-not $Quiet) {
                Write-Warn "$Label 미주입 — 1Password에서 값을 읽지 못했습니다 ($Hint) → 건너뜀 (1Password 앱 > 설정 > 개발자 > '1Password CLI와 통합' 확인 후 .\win-setup.ps1 -EnvOnly 재실행)"
            }
            return $false
        }
        $values += $val
    }

    for ($i = 0; $i -lt $Names.Count; $i++) {
        try { Set-UserEnv $Names[$i] $values[$i] | Out-Null }
        catch {
            if (-not $Quiet) { Write-Warn "$Label 저장 실패 → 건너뜀 (수동 설정: 시작 > '계정의 환경 변수 편집'에서 직접 추가)" }
            return $false
        }
    }

    if (-not $Quiet) {
        Write-Ok "$Label 주입 완료 (사용자 환경변수 — 값은 1Password에만 있고 이 저장소에는 들어가지 않습니다)"
    }
    return $true
}

# 1Password CLI 설정 안내 — '왜 필요한지 → 무엇을 누르는지 → 어떻게 확인하는지' 순서로 읽히게 유지합니다.
function Show-CocodeOpGuide {
    Write-Host ""
    Write-Host "  ⏸  팀 토큰을 가져오려면 1Password CLI 설정이 필요합니다."
    Write-Host ""
    Write-Host "     [무엇을 하는 건가요?]"
    Write-Host "     ZenHub·Jira 같은 서비스를 쓰려면 비밀번호 같은 '토큰' 값이 필요합니다. 이 값은 팀 공용"
    Write-Host "     1Password 금고에 들어 있고, 1Password CLI(op)가 그 금고를 대신 열어 읽어옵니다."
    Write-Host "     아래 설정은 op에게 '1Password 앱에 이미 로그인된 상태를 그대로 써도 된다'고 허락해 주는 과정입니다."
    Write-Host "     (토큰 값은 1Password에만 저장되고, 이 저장소(git)에는 절대 들어가지 않습니다.)"
    Write-Host ""
    Write-Host "     [설정 방법 — 1Password 앱에서]"
    Write-Host "       1) 1Password 앱을 열고 팀 계정($opAccountLabel)으로 로그인"
    Write-Host "       2) 앱 메뉴 > 설정(Ctrl+,) > '개발자' 탭 > '1Password CLI와 통합' 체크"
    Write-Host "          · '개발자' 탭이 안 보이면: 설정 > 보안 > 'Windows Hello로 잠금 해제'를 먼저 켜세요"
    Write-Host "          · 터미널을 이미 열어둔 상태였다면 체크 후 이 창에서 Enter만 누르면 됩니다"
    Write-Host ""
    Write-Host "     [잘 됐는지 확인하려면 — 새 터미널 창에서]"
    Write-Host "       op account list   ← 팀 계정($opAccountLabel)이 목록에 보이면 성공"
    Write-Host "                            · 목록이 비어 있으면 위 2번 체크가 아직 안 된 것입니다"
    Write-Host "                            · 몇 초 멈추면 1Password 앱이 잠금 해제(Windows Hello)를 기다리는 중입니다"
    Write-Host ""
    Write-Host "     ※ 'op account add'를 직접 입력할 필요는 없습니다 — 앱 통합을 켜면 계정이 자동 등록됩니다."
    Write-Host "     ※ 계정 목록에는 보이는데 계속 실패한다면 팀 'API Token' 금고 접근 권한이 없는 경우입니다."
    Write-Host "        이때는 팀 관리자에게 해당 금고 공유를 요청해 주세요."
    Write-Host ""
}

Write-Step "8.5-a. ZENHUB_API_TOKEN 주입 (1Password 팀 공용 토큰)"

# op는 앞 단계에서 설치됐어야 하지만, 없으면 여기서 한 번 더 시도합니다.
if (-not (Test-Cmd 'op')) {
    Install-Winget -Id 'AgileBits.1Password.CLI' -Name '1Password CLI (op)' -ProbeCmd 'op' | Out-Null
}

if (-not (Test-Cmd 'op')) {
    $OpStatus = 'missing'
    Write-Warn "op(1Password CLI) 미설치 → 토큰 주입을 건너뜁니다 (수동 설치: winget install --id AgileBits.1Password.CLI -e --source winget 후 .\win-setup.ps1 -EnvOnly)"
}
elseif (Set-CocodeTeamSecret -Names @('ZENHUB_API_TOKEN') -Refs @($ZenhubTokenOpRef) -Label 'ZENHUB_API_TOKEN' -Hint "팀 'API Token' 금고 > 'ZenHub API Token'" -Quiet) {
    $OpStatus = 'ready'
    Write-Ok "ZENHUB_API_TOKEN 주입 완료 (사용자 환경변수 — 값은 1Password에만 있고 이 저장소에는 들어가지 않습니다)"
}
elseif (Test-Interactive) {
    # 대화형이면 1Password 설정을 마칠 때까지 안내하고 Enter로 다시 시도합니다.
    $OpStatus = 'not-ready'
    while ($true) {
        Show-CocodeOpGuide
        $opAnswer = Read-Host "     설정을 마쳤으면 Enter(재시도) · 나중에 하려면 s 입력 후 Enter"
        if ($opAnswer -eq 's' -or $opAnswer -eq 'S') {
            Write-Warn "ZENHUB_API_TOKEN 주입 건너뜀 → 1Password 설정을 마친 뒤 .\win-setup.ps1 -EnvOnly 로 토큰만 다시 주입할 수 있습니다"
            break
        }
        if (Set-CocodeTeamSecret -Names @('ZENHUB_API_TOKEN') -Refs @($ZenhubTokenOpRef) -Label 'ZENHUB_API_TOKEN' -Hint "팀 'API Token' 금고 > 'ZenHub API Token'" -Quiet) {
            $OpStatus = 'ready'
            Write-Ok "ZENHUB_API_TOKEN 주입 완료 (사용자 환경변수 — 값은 1Password에만 있고 이 저장소에는 들어가지 않습니다)"
            break
        }
        Write-Info "아직 토큰을 읽지 못했습니다 — 위 2번('1Password CLI와 통합' 체크)이 켜졌는지, 팀 'API Token' 금고 접근 권한이 있는지 확인한 뒤 다시 Enter를 누르세요"
    }
}
else {
    # 비대화형(자동 실행): 멈추지 않고 안내만 남깁니다.
    $OpStatus = 'not-ready'
    Write-Warn "ZENHUB_API_TOKEN 미주입 (비대화형 실행) → 건너뜀 (1Password 앱 > 설정 > 개발자 > '1Password CLI와 통합' 체크 후 .\win-setup.ps1 -EnvOnly 재실행)"
}

Write-Step "8.5-b. JIRA_API_TOKEN 주입 (1Password 팀 공용 계정 Jira 토큰, mcp-atlassian용)"
Set-CocodeTeamSecret -Names @('JIRA_API_TOKEN') -Refs @($JiraTokenOpRef) -Label 'JIRA_API_TOKEN' -Hint "팀 'API Token' 금고 > 'Laputa Atlassian API Token' > 'Jira API Token' 필드" | Out-Null

Write-Step "8.5-c. SLANG_GPT_API_KEY 주입 (1Password 팀 공용 키, slang_gpt 다국어 자동 번역용)"
Set-CocodeTeamSecret -Names @('SLANG_GPT_API_KEY') -Refs @($SlangGptTokenOpRef) -Label 'SLANG_GPT_API_KEY' -Hint "팀 'API Token' 금고 > 'Slang GPT API Token' > credential 필드" | Out-Null

Write-Step "8.5-d. DCM_EMAIL·DCM_CI_KEY 주입 (1Password 팀 공용 항목 'DCM CI CD', DCM 라이선스 인증용)"
# 이메일과 키가 둘 다 있어야 인증되므로, 하나라도 못 읽으면 아예 넣지 않습니다.
Set-CocodeTeamSecret -Names @('DCM_EMAIL', 'DCM_CI_KEY') -Refs @($DcmEmailOpRef, $DcmCiKeyOpRef) -Label 'DCM_EMAIL·DCM_CI_KEY' -Hint "팀 'API Token' 금고 > 'DCM CI CD' 항목의 username·credential 필드" | Out-Null

Write-Step "8.5-e. SLACK_TEAM_ID·SLACK_BOT_TOKEN 주입 (1Password 팀 공용 항목 'Cocode Slack', slack MCP용)"
Set-CocodeTeamSecret -Names @('SLACK_TEAM_ID', 'SLACK_BOT_TOKEN') -Refs @($SlackTeamIdOpRef, $SlackBotTokenOpRef) -Label 'SLACK_TEAM_ID·SLACK_BOT_TOKEN' -Hint "팀 'API Token' 금고 > 'Cocode Slack' 항목의 SLACK_TEAM_ID·SLACK_BOT_TOKEN 필드" | Out-Null

Write-Step "8.5-f. TYPESAFE_API_KEY 주입 (1Password 팀 공용 항목 'TypeSafe Jev', TypeSafe SDK용)"
# TypeSafe(판단형 AI 모델 Jev) 공식 SDK(Python·JavaScript)가 이 환경변수를 알아서 읽습니다.
# MCP 등록이 없는 단일 값이라 Slang GPT(8.5-c)와 같은 방식으로 넣기만 하면 됩니다.
Set-CocodeTeamSecret -Names @('TYPESAFE_API_KEY') -Refs @($TypesafeTokenOpRef) -Label 'TYPESAFE_API_KEY' -Hint "팀 'API Token' 금고 > 'TypeSafe Jev' > credential 필드" | Out-Null

Write-Step "8.5-g. OPENAI_API_KEY 주입 (1Password 팀 공용 항목 'OPENAI_API_KEY', OpenAI SDK용)"
# OpenAI 공식 SDK(Python·JavaScript)가 이 환경변수를 알아서 읽습니다.
# MCP 등록이 없는 단일 값이라 Slang GPT(8.5-c)·TypeSafe(8.5-f)와 같은 방식으로 넣기만 하면 됩니다.
# slang_gpt(8.5-c)는 이 변수가 아니라 자기 전용 SLANG_GPT_API_KEY를 읽습니다 — 두 변수는 서로 별개입니다.
# ⚠ 이미 사용자 환경변수 OPENAI_API_KEY 를 직접 설정해 두었다면 팀 키로 바뀝니다 (다른 팀 토큰과 같은 동작).
Set-CocodeTeamSecret -Names @('OPENAI_API_KEY') -Refs @($OpenaiTokenOpRef) -Label 'OPENAI_API_KEY' -Hint "팀 'API Token' 금고 > 'OPENAI_API_KEY' > credential 필드" | Out-Null

# ★맥의 `source ~/.zshrc`에 해당하는 수단이 윈도우에는 없습니다.
#   프로그램은 실행되는 순간의 환경변수를 복사해 갖고 있을 뿐이라, 이미 열려 있던 창은
#   새 값을 절대 못 봅니다. 이 안내를 놓치면 "토큰을 넣었는데 MCP가 안 붙는" 것처럼 보입니다.
Write-Info "토큰은 '지금 이 창'과 '앞으로 새로 여는 창'에만 적용됩니다"
Write-Info "↳ 이미 실행 중인 Claude Code·Windows Terminal·VS Code는 완전히 종료했다가 다시 실행하세요 (창만 닫지 말고 프로그램 종료)"

}



# ══════════════════════════════════════════════════════════════
# 10단계 — 설치 검증 + 다음 단계 안내 (전체 설치일 때만)
# ══════════════════════════════════════════════════════════════
if ($RunInstall) {

# ============================================================
# 10. 설치 검증 + 다음 단계 안내
#
#   맥 스크립트의 10단계와 같은 역할 — 방금 깐 것들의 버전을 한 화면에 뿌려서
#   "무엇이 되고 무엇이 안 됐는지"를 스크롤 한 번으로 확인하게 한다.
#   ❌ 옆에는 항상 **직접 고칠 수 있는 명령**을 함께 적는다.
# ============================================================
Write-Step "10. 설치 검증"

# 아래 검증 줄들은 앞 단계에서 만든 변수를 참고한다. 어떤 단계가 통째로 실패해
# 변수가 안 만들어졌을 수도 있으므로, 여기서 빈 기본값을 먼저 채워 둔다
# (검증하다가 스크립트가 죽는 일이 없게).
if ($null -eq $GuiApps)          { $GuiApps = @() }
if ($null -eq $AndroidSdkHome)   { $AndroidSdkHome = '' }
if ($null -eq $AndroidJavaHome)  { $AndroidJavaHome = '' }
if ($null -eq $AndroidNdkHome)   { $AndroidNdkHome = '' }
if ($null -eq $AndroidAvdName)   { $AndroidAvdName = '' }
if ($null -eq $AndroidAccelMsg)  { $AndroidAccelMsg = '확인하지 못했습니다 (Android 단계가 실행되지 않았습니다)' }
if ($null -eq $CocodeProfilePath){ $CocodeProfilePath = '' }
if ($null -eq $CocodeOmpTheme)   { $CocodeOmpTheme = 'powerlevel10k_rainbow' }
if ($null -eq $CocodeFontFace)   { $CocodeFontFace = 'MesloLGS NF' }
if ($null -eq $wtSettings)       { $wtSettings = '' }
if ($null -eq $OpStatus)         { $OpStatus = 'missing' }
if ($null -eq $ArchIsArm64)      { $ArchIsArm64 = $false }

# Windows 앱 빌드 도구(Visual Studio) — 4-a-7 단계가 vswhere 로 계산해 둔 $vsFound 를 그대로 쓴다.
#   폴더 존재만 보면 C++ 워크로드 없이 깔린 Visual Studio 도 '설치됨'으로 나오기 때문이다.
#   그 단계가 실행되지 않았거나 이번 실행에서 방금 설치했다면 여기서 한 번 더 확인한다.
if ($null -eq $vsFound)          { $vsFound = $false }
if (-not $vsFound) {
    $vsPfChk = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($vsPfChk)) { $vsPfChk = $env:ProgramFiles }
    $vsWhereChk = Join-Path $vsPfChk 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vsWhereChk) {
        try {
            $vsPathChk = & $vsWhereChk -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' 'Microsoft.VisualStudio.Component.VC.CMake.Project' -property installationPath 2>$null
            if (-not [string]::IsNullOrWhiteSpace(($vsPathChk | Out-String))) { $vsFound = $true }
        } catch { }
    }
}

Write-Host ''
Write-Host '── 패키지 관리자 ─────────────────────────────' -ForegroundColor DarkCyan
Write-Host ("winget  : " + $(if (Test-Cmd 'winget') { (& winget --version 2>&1 | Select-Object -First 1) } else { '❌ 없음 (Microsoft Store에서 앱 설치 관리자 설치)' }))
Write-Host ("scoop   : " + $(if (Test-Cmd 'scoop') { (& scoop --version 2>&1 | Select-Object -First 1) } else { '❌ 없음 (관리자가 아닌 PowerShell에서: irm get.scoop.sh | iex)' }))
Write-Host ("scoop 버킷: " + $(if (Test-Cmd 'scoop') { (((& scoop bucket list 2>&1 | Out-String) -split "`n" | Where-Object { $_ -match '^\s*(extras|versions|java)\b' }).Count.ToString() + '/3 등록됨') } else { '❌ 확인 불가' }))

Write-Host ''
Write-Host '── 셸 · 터미널 ───────────────────────────────' -ForegroundColor DarkCyan
Write-Host "  pwsh      : $($PSVersionTable.PSVersion) (에디션: $($PSVersionTable.PSEdition))"
Write-Host "  실행 정책  : $(Get-ExecutionPolicy -Scope CurrentUser) $(if (@('RemoteSigned','Unrestricted','Bypass') -contains [string](Get-ExecutionPolicy -Scope CurrentUser)) { '✓' } else { '❌ 프로필이 안 읽힙니다 (Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser)' })"
Write-Host "  프로필     : $(if ($CocodeProfilePath -and (Test-Path -LiteralPath $CocodeProfilePath) -and (Select-String -LiteralPath $CocodeProfilePath -Pattern 'co:code 공용 설정 시작' -Quiet)) { '✓ ' + $CocodeProfilePath } else { '❌ 미설정 (.\win-setup.ps1 재실행)' })"
Write-Host "  프롬프트(oh-my-posh): $(if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) { '✓ 설치됨 (테마: ' + $CocodeOmpTheme + ' — 새 터미널부터 보입니다)' } else { '❌ (수동 설치: winget install --id JanDeDobbeleer.OhMyPosh -e --source winget)' })"
Write-Host "  자동 제안(PSReadLine): $(if ((Get-Module PSReadLine -ListAvailable) -and ((Get-Module PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version -ge [version]'2.2.0')) { '✓ 지원 버전 (예전 명령을 회색으로 미리 보여 줍니다)' } else { '❌ (수동 설치: Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber)' })"
Write-Host "  폰트(MesloLGS NF): $(if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\MesloLGS NF Regular.ttf')) { '✓ 설치됨' } else { '❌ (수동 설치: https://github.com/romkatv/powerlevel10k/blob/master/font.md)' })"
Write-Host "  Windows Terminal 폰트: $(if ($wtSettings -and (Select-String -LiteralPath $wtSettings -Pattern 'MesloLGS NF' -Quiet -ErrorAction SilentlyContinue)) { '✓ MesloLGS NF 적용됨 (터미널을 껐다 켜야 보입니다)' } else { '❌ 미적용 (설정 > 기본값 > 모양 > 글꼴에서 MesloLGS NF 선택)' })"

Write-Host ''
Write-Host '── CLI 도구 ──────────────────────────────────' -ForegroundColor DarkCyan
# winget list 전체 출력을 한 문자열로 훑으면, 콘솔 폭이 좁을 때 긴 패키지 ID 가 '…' 로 잘려
# 멀쩡히 깔린 앱이 '❌ 없음' 으로 나온다. 그래서 앱마다 Test-WingetInstalled 로 정확히 확인한다.
Write-Host 'GUI 앱  :'
foreach ($a in $GuiApps) {
  if ($a.X64Only -and $ArchIsArm64) {
    $mark = '— ARM64 미지원(건너뜀 · 제조사 홈페이지에서 직접 내려받아 설치)'
  } elseif (Test-WingetInstalled $a.Id) {
    $mark = '✓ 설치됨'
  } else {
    $mark = '❌ 없음 (winget install --id ' + $a.Id + ' -e --source winget)'
  }
  Write-Host ("  " + $a.Name.PadRight(34) + ": " + $mark)
}
Write-Host ("op(1Password CLI): " + $(if (Test-Cmd 'op') { (& op --version 2>&1 | Select-Object -First 1) } else { '❌ 없음 (winget install --id AgileBits.1Password.CLI -e --source winget 후 .\win-setup.ps1 -EnvOnly · 명령이 안 잡히면 설정 > 시스템 > 개발자용에서 개발자 모드 켜기)' }))
Write-Host ("Lumide  : " + $(if (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Lumide')) { '✓ 설치됨' } else { '❌ 없음 (github.com/SoFluffyOS/lumide/releases)' }))
Write-Host ("Rive    : " + $(if ((Initialize-AppxModule) -and (Get-AppxPackage -Name '*Rive*' -ErrorAction SilentlyContinue)) { '✓ 설치됨' } else { '❌ 없음 (브라우저 에디터 editor.rive.app 사용 가능)' }))
$PfCount = @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts') -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Pretendard-*.ttf' -or $_.Name -like 'Pretendard-*.otf' } | Group-Object BaseName).Count; Write-Host ("Pretendard: " + $(if ($PfCount -ge 9) { "✓ $PfCount 종 설치됨 (앱을 껐다 켜야 반영됩니다)" } else { "⚠ $PfCount 종만 설치됨 (9종 필요)" }))
Write-Host ("  git      : " + $(if (Test-Cmd 'git') { (& git --version) } else { '❌ (수동 설치: winget install -e --id Git.Git)' }))
Write-Host ("  git 설정  : " + $(if (Test-Cmd 'git') { ('longpaths=' + "$(& git config --get core.longpaths 2>$null)".Trim() + ' · autocrlf=' + "$(& git config --global --get core.autocrlf 2>$null)".Trim() + ' (longpaths는 true, autocrlf는 false 여야 정상)') } else { '❌ (git 미설치)' }))
Write-Host ("  git email : " + $(if (Test-Cmd 'git') { $gitEmail = "$(& git config --global user.email 2>$null)".Trim(); if ($gitEmail) { $gitEmail } else { '❌ 미설정 (git config --global user.email 이름@cocode.im)' } } else { '❌ (git 미설치)' }))
Write-Host ("  go       : " + $(if (Test-Cmd 'go') { (& go version) } elseif (Test-Path (Join-Path $env:ProgramFiles 'Go\bin\go.exe')) { '✓ 설치됨 (새 터미널에서 PATH 반영)' } else { '❌ (수동 설치: winget install -e --id GoLang.Go)' }))
Write-Host ("  pyenv    : " + $(if (Test-Cmd 'pyenv') { '✓ 설치됨' } elseif (Test-Path (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\bin\pyenv.bat')) { '✓ 설치됨 (새 터미널에서 PATH 반영)' } else { '❌ (수동 설치: pyenv-win 공식 install-pyenv-win.ps1 실행 · scoop 판은 설치 위치가 달라 동작하지 않습니다)' }))
Write-Host ("  nvm/fnm  : " + $(if (Test-Cmd 'nvm') { ('nvm ' + "$(& nvm version 2>$null)".Trim() + ' (nvm use 는 관리자 터미널에서)') } elseif (Test-Cmd 'fnm') { ('fnm ' + "$(& fnm --version 2>$null)".Trim()) } else { '❌ (수동 설치: winget install -e --id CoreyButler.NVMforWindows · 기존 Node.js가 있으면 먼저 제거)' }))
Write-Host ("  gh       : " + $(if (Test-Cmd 'gh') { ((& gh --version 2>$null) | Select-Object -First 1) } else { '❌ (수동 설치: winget install -e --id GitHub.cli)' }))
Write-Host ("  jq       : " + $(if (Test-Cmd 'jq') { (& jq --version) } else { '❌ (수동 설치: winget install -e --id jqlang.jq)' }))
Write-Host ("  aws      : " + $(if (Test-Cmd 'aws') { (& aws --version 2>&1 | Select-Object -First 1) } elseif (Test-Path (Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe')) { '✓ 설치됨 (새 터미널에서 PATH 반영)' } else { '❌ (수동 설치: winget install -e --id Amazon.AWSCLI)' }))
Write-Host ("  java     : " + $(if (Test-Cmd 'java') { ((& java -version 2>&1) | Select-Object -First 1) } else { '❌ (수동 설치: winget install -e --id EclipseAdoptium.Temurin.17.JDK)' }))
Write-Host ("  JAVA_HOME: " + $(if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) { $env:JAVA_HOME } else { '❌ 미설정 (JDK 17 설치 후 스크립트를 다시 실행하세요)' }))
Write-Host ("  docker   : " + $(if (Test-Cmd 'docker') { ((& docker --version 2>&1) | Select-Object -First 1) } else { '❌ (수동 설치: winget install -e --id Docker.DockerDesktop · 설치 후 재부팅 + 앱 최초 1회 실행)' }))
Write-Host ("  docker compose: " + $(if (Test-Cmd 'docker') { ((& docker compose version 2>&1) | Select-Object -First 1) } else { '❌ (Docker Desktop 설치 필요 — compose는 별도 설치하지 않고 docker compose 로 사용)' }))
Write-Host ("  direnv   : " + $(if (Test-Cmd 'direnv') { ((& direnv --version 2>$null) + ' (셸 연결: ' + $(if ((Test-Path $PROFILE.CurrentUserAllHosts) -and ((Get-Content $PROFILE.CurrentUserAllHosts -Raw -ErrorAction SilentlyContinue) -like '*direnv hook pwsh*')) { '✓ 등록됨' } else { '❌ 미등록' }) + ')') } else { '❌ (수동 설치: winget install -e --id direnv.direnv)' }))
Write-Host ("  lefthook : " + $(if (Test-Cmd 'lefthook') { ((& lefthook version 2>$null) + ' (레포마다 lefthook install 1회 필요)') } else { '❌ (수동 설치: winget install -e --id evilmartians.lefthook)' }))

Write-Host ''
Write-Host '── Flutter · Dart ────────────────────────────' -ForegroundColor DarkCyan
Write-Host ("  개발자 모드   : " + $(if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1) { '✓ 켜짐' } else { '❌ 꺼짐 (start ms-settings:developers 로 켜고 재부팅 — 이게 없으면 Flutter 앱 빌드가 실패합니다)' }))
Write-Host ("  긴 경로 해제  : " + $(if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled -eq 1) { '✓ 적용됨 (재부팅 후 유효)' } else { '❌ 미적용 (관리자 PowerShell 에서 New-ItemProperty -Path ''HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'' -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force)' }))
Write-Host ("  git 안전 폴더 : " + $(if ((& git config --global --get-all safe.directory 2>$null) -contains '*') { '✓ 설정됨' } else { '❌ 미설정 (git config --global --add safe.directory "*") — 없으면 fvm 이 unable to find git 오류를 냅니다' }))
Write-Host ("  fvm     : " + $(if (Test-Cmd 'fvm') { ((& fvm --version 2>$null) | Select-Object -First 1) } else { '❌ (수동 설치: https://fvm.app/documentation/getting-started/installation)' }))
Write-Host ("  flutter : " + $(if (Test-Cmd 'flutter') { ((& flutter --version 2>$null) | Select-Object -First 1) } else { "❌ (fvm global $TeamFlutterVersion --force 실행 후 새 터미널에서 확인)" }))
Write-Host ("  dart    : " + $(if (Test-Cmd 'dart') { (((& dart --version 2>$null) | Out-String).Trim()) } else { '❌ (새 터미널에서 다시 확인)' }))
Write-Host ("  Flutter PATH: " + $(if ($env:Path -like '*fvm*default*bin*') { '✓ 등록됨' } else { "❌ 미등록 (새 터미널에서 확인 — 그래도 없으면 fvm global $TeamFlutterVersion --force 재실행)" }))
Write-Host ("  Windows 빌드도구: " + $(if ($vsFound) { '✓ 설치됨 (C++ 빌드 도구 확인됨 · 자세한 확인: flutter doctor -v)' } else { '❌ 미설치 — Windows 데스크톱 앱 빌드에 필요 (수동 설치: winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget · 설치 화면에서 ''C++를 사용한 데스크톱 개발'' 선택 · 자세한 확인: flutter doctor -v)' }))
$dartList = $(if (Test-Cmd 'dart') { ((& dart pub global list 2>$null) | Out-String) } else { '' })
$dartMissing = @('coverage','melos','mason_cli','flutter_gen','jaspr_cli','serverpod_cli','flutterfire_cli','marionette_mcp','mcp_server_dart') | Where-Object { $dartList -notmatch ('(?m)^' + [regex]::Escape($_) + ' ') }
Write-Host ("  dart 글로벌 패키지: " + $(if ($dartMissing) { '❌ 누락: ' + ($dartMissing -join ', ') + ' (네트워크 확인 후 스크립트 재실행)' } else { '✓ coverage, melos, mason_cli, flutter_gen, jaspr_cli, serverpod_cli, flutterfire_cli, marionette_mcp, mcp_server_dart' }))
Write-Host ("  cob(co-bricks): " + $(if ($dartList -match '(?m)^(cob|co_bricks) ') { '✓' } else { '❌ (GitHub 인증 후 재실행 — gh auth login → gh auth setup-git)' }))
Write-Host ("  gcloud  : " + $(if (Test-Cmd 'gcloud') { ((& gcloud --version 2>$null) | Select-Object -First 1) } else { '❌ (수동 설치: https://cloud.google.com/sdk/docs/install)' }))
Write-Host ("  dcm     : " + $(if (Test-Cmd 'dcm') { ((& dcm --version 2>$null) | Select-Object -First 1) } else { '❌ (수동 설치: https://dcm.dev/docs/getting-started/for-developers/installation/)' }))

Write-Host ''
Write-Host '── Android ───────────────────────────────────' -ForegroundColor DarkCyan
if ($AndroidJavaHome -and (Test-Path (Join-Path $AndroidJavaHome 'bin\java.exe'))) { Write-Host "  jdk     : ✓ $AndroidJavaHome" } else { Write-Host "  jdk     : ❌ (수동: winget install --exact --id EclipseAdoptium.Temurin.17.JDK)" }
if ($AndroidSdkHome -and (Test-Path (Join-Path $AndroidSdkHome 'platform-tools\adb.exe'))) { Write-Host "  android : ✓ $AndroidSdkHome" } else { Write-Host "  android : ❌ (Android Studio 첫 실행 마법사로 수동 설치 가능)" }
if ($AndroidNdkHome -and (Test-Path $AndroidNdkHome)) { Write-Host "  ndk     : ✓ $AndroidNdkHome" } else { Write-Host "  ndk     : ❌ (수동: sdkmanager 'ndk;28.2.13676358')" }
if ($AndroidAvdName) { Write-Host "  avd     : ✓ $AndroidAvdName" } else { Write-Host "  avd     : ❌ (Android Studio > Device Manager 에서 수동 생성 가능)" }
Write-Host "  에뮬가속: $AndroidAccelMsg"

Write-Host ''
Write-Host '── AI 코딩 도구 · MCP ────────────────────────' -ForegroundColor DarkCyan
Write-Host ("  claude  : " + $(if (Test-Cmd 'claude') { $v = (& claude --version 2>$null | Select-Object -First 1); if ($v) { $v } else { "✓ 설치됨" } } else { "❌ (수동 설치: irm https://claude.ai/install.ps1 | iex)" }))
Write-Host ("  opencode: " + $(if (Test-Cmd 'opencode') { & opencode --version 2>$null } else { "❌ (수동 설치: npm install -g opencode-ai)" }))
Write-Host ("  codex   : " + $(if (Test-Cmd 'codex') { $v = (& codex --version 2>$null | Select-Object -First 1); if ($v) { $v } else { "✓ 설치됨" } } else { "❌ (수동 설치: irm https://chatgpt.com/codex/install.ps1 | iex)" }))
Write-Host ("  agy(antigravity): " + $(if (Test-Cmd 'agy') { "✓ 설치됨 (최초 실행 시 agy 로 Google 로그인)" } else { "❌ (수동 설치: irm https://antigravity.google/cli/install.ps1 | iex)" }))
Write-Host ("  slack   : " + $(if (Test-Cmd 'slack') { $v = (& slack version 2>$null | Select-Object -First 1); if ($v) { $v } else { "✓ 설치됨" } } else { "❌ (수동 설치: PowerShell 7에서 irm https://downloads.slack-edge.com/slack-cli/install-windows.ps1 | iex)" }))
Write-Host ("  Claude Bash 경로: " + $(if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path $env:CLAUDE_CODE_GIT_BASH_PATH)) { "✓ " + $env:CLAUDE_CODE_GIT_BASH_PATH } else { "❌ (Git for Windows 확인 — 없으면 Claude Code가 Bash 대신 PowerShell을 씁니다)" }))
$ghOk = $false; if (Test-Cmd 'gh') { & gh auth status 2>&1 | Out-Null; $ghOk = ($LASTEXITCODE -eq 0) }; Write-Host ("  GitHub 인증(gh): " + $(if ($ghOk) { "✓ 인증됨" } else { "❌ (1Password 'API Token' 볼트의 'GitHub API Token' 확인 · 수동: gh auth login)" }))
# 연결을 시도하지 않고 설정 파일의 등록 여부만 확인합니다. 인증은 새 세션에서 확인합니다.
foreach ($mcpClient in @('claude', 'opencode')) {
    $cfg = $null; $mcpKey = 'mcpServers'; $mcpConfig = Join-Path $env:USERPROFILE '.claude.json'
    if ($mcpClient -eq 'opencode') { $mcpKey = 'mcp'; $mcpConfig = $OpenCodeConfigPath }
    try { $cfg = [IO.File]::ReadAllText($mcpConfig) | ConvertFrom-Json -ErrorAction Stop } catch { }
    foreach ($name in @('cob','dart','figma','marionette','atlassian','mobbin','slack','zenhub','chrome-devtools','playwright')) {
        $state = '❌ 미등록 (.\win-setup.ps1 재실행 · 6.6단계 확인)'
        if ($null -ne $cfg -and $null -ne $cfg.$mcpKey -and $null -ne $cfg.$mcpKey.$name) {
            $state = '✓ 등록됨 (연결·인증은 새 세션에서 확인)'
        }
        Write-Host "  mcp:${mcpClient}:${name}: $state"
    }
}
# 3.5단계와 같은 기준으로 본다 — 버전 스탬프 파일 또는 마켓플레이스 plugins 폴더 중 하나만 있으면 설치된 것.
$csStamp = Join-Path $env:USERPROFILE '.claude\skills\.cocode-skills-version'
$csMarket = Join-Path $env:USERPROFILE '.claude\plugins\marketplaces\cocode-skills\plugins'
$csCount = 0
if (Test-Path $csMarket) { $csCount = @(Get-ChildItem $csMarket -Directory -ErrorAction SilentlyContinue).Count }
Write-Host ("  cocode-skills: " + $(if ((Test-Path $csStamp) -or (Test-Path $csMarket)) { $(if ($csCount -gt 0) { "✓ ${csCount}개 스킬" } else { "✓ 설치됨" }) } else { "❌ (원인 둘 중 하나 — ① gh 인증이 없으면: gh auth login → gh auth setup-git → .\win-setup.ps1  ② 위 3.5단계에 'rsync' 경고가 떴다면 재실행해도 해결되지 않습니다: coco-de/skills 레포에 install.ps1 이 추가돼야 하며, 그때까지는 팀원의 %USERPROFILE%\.claude 폴더를 복사해 쓰세요)" }))
Write-Host "  상태줄(statusline): $(if ((Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude\settings.json')) -and (Select-String -LiteralPath (Join-Path $env:USERPROFILE '.claude\settings.json') -Pattern 'statusLine' -Quiet)) { '✓ 등록됨 (Claude Code에서 적용)' } else { '❌ 미등록 (수동 설정: npx -y ccstatusline@latest)' })"

Write-Host ''
Write-Host '── 런타임 ────────────────────────────────────' -ForegroundColor DarkCyan
Write-Host "  python    : $(if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\bin\pyenv.bat')) { (& (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\bin\pyenv.bat') version 2>$null | Select-Object -First 1) } else { '❌ (수동 설치: https://github.com/pyenv-win/pyenv-win#installation)' })"
Write-Host "  node      : $(if (Get-Command node -ErrorAction SilentlyContinue) { (node --version 2>$null) } else { '❌ (관리자 터미널에서: winget install --id CoreyButler.NVMforWindows -e → nvm install lts → nvm use lts)' })"
Write-Host "  npm       : $(if (Get-Command npm -ErrorAction SilentlyContinue) { (npm --version 2>$null) } else { '❌ (Node.js를 설치하면 함께 들어옵니다)' })"

Write-Host ''
Write-Host '── 윈도우 시스템 설정 · 브라우저 ─────────────' -ForegroundColor DarkCyan
Write-Host "  ZenHub 확장(Chrome): $(if ((Test-Path 'HKLM:\SOFTWARE\Wow6432Node\Google\Chrome\Extensions\ogcgkffhplmphkaahpmffcafajaocjbd') -or (Test-Path 'HKLM:\SOFTWARE\Google\Chrome\Extensions\ogcgkffhplmphkaahpmffcafajaocjbd')) { '✓ 등록됨 (Chrome 실행 후 확인 창에서 확장 사용 클릭 필요)' } else { '❌ (수동 설치: https://chromewebstore.google.com/detail/zenhub-for-github/ogcgkffhplmphkaahpmffcafajaocjbd)' })"
Write-Host "  ZenHub 확장(Edge)  : $(if ((Test-Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Edge\Extensions\ogcgkffhplmphkaahpmffcafajaocjbd') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Edge\Extensions\ogcgkffhplmphkaahpmffcafajaocjbd')) { '✓ 등록됨 (Edge 실행 후 확인 창에서 확장 사용 클릭 필요)' } else { '❌ (수동 설치: https://chromewebstore.google.com/detail/zenhub-for-github/ogcgkffhplmphkaahpmffcafajaocjbd)' })"
Write-Host "  Edge 다른 스토어 확장 허용: $(if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended' -Name ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled -ErrorAction SilentlyContinue).ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled -eq 1) { '✓ 켜짐' } else { '❌ (edge://extensions 에서 다른 스토어의 확장 허용 토글을 직접 켜기)' })"
Write-Host "  브라우저 번역(Chrome): $(if ((Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Preferences')) -and ((Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Preferences') -Raw -Encoding UTF8 | ConvertFrom-Json).translate_recent_target -eq 'ko')) { '✓ 한국어로 번역 설정됨' } else { '❌ (chrome://settings/languages 에서 직접 설정 · Chrome 완전 종료 후 스크립트 재실행)' })"
Write-Host "  브라우저 번역(Edge)  : $(if ((Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Preferences')) -and ((Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Preferences') -Raw -Encoding UTF8 | ConvertFrom-Json).translate_recent_target -eq 'ko')) { '✓ 한국어로 번역 설정됨' } else { '❌ (edge://settings/languages 에서 직접 설정 · Edge 완전 종료 후 스크립트 재실행)' })"
Write-Host "  개발자 모드: $(if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1) { '✓ 켜짐 (Flutter 플러그인 빌드 가능)' } else { '❌ 꺼짐 — 켜지 않으면 Flutter 빌드 실패 (설정 > 시스템 > 개발자용, 또는 start ms-settings:developers)' })"
Write-Host "  긴 경로 허용: $(if ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled -eq 1) { '✓ 켜짐 (재부팅 후 적용 · 레포는 C:\src 처럼 짧은 경로 권장)' } else { '❌ (관리자 PowerShell에서 재실행하거나 LongPathsEnabled=1 직접 설정)' })"
Write-Host "  Git 긴 경로(core.longpaths): $(if ((Test-Cmd 'git') -and ((((& git config --system --get core.longpaths) -eq 'true')) -or (((& git config --global --get core.longpaths) -eq 'true')))) { '✓ 켜짐' } else { '❌ (수동: git config --global core.longpaths true)' })"

Write-Host ''
Write-Host '── 팀 공용 토큰 (1Password) ──────────────────' -ForegroundColor DarkCyan
Write-Host "  op(1Password CLI): $(if ($OpStatus -eq 'ready') { '✓ 설치 + 팀 계정 연결됨' } elseif ($OpStatus -eq 'not-ready') { '⚠ 설치됨 (설정 미완료 — 1Password 앱 > 설정 > 개발자 > 1Password CLI와 통합 체크 후 .\win-setup.ps1 -EnvOnly)' } else { '❌ (winget install --id AgileBits.1Password.CLI -e --source winget 후 .\win-setup.ps1 -EnvOnly)' })"
Write-Host "  ZENHUB_API_TOKEN: $(if ([Environment]::GetEnvironmentVariable('ZENHUB_API_TOKEN','User')) { '✓ 주입됨 (새로 여는 창부터 적용 — zenhub MCP용)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"
Write-Host "  JIRA_API_TOKEN: $(if ([Environment]::GetEnvironmentVariable('JIRA_API_TOKEN','User')) { '✓ 주입됨 (새로 여는 창부터 적용 — mcp-atlassian용, docker 실행 중이어야 함)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"
Write-Host "  SLANG_GPT_API_KEY: $(if ([Environment]::GetEnvironmentVariable('SLANG_GPT_API_KEY','User')) { '✓ 주입됨 (slang_gpt 다국어 자동 번역용)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"
Write-Host "  DCM_EMAIL/DCM_CI_KEY: $(if (([Environment]::GetEnvironmentVariable('DCM_EMAIL','User')) -and ([Environment]::GetEnvironmentVariable('DCM_CI_KEY','User'))) { '✓ 주입됨 (DCM CI 라이선스 인증용)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"
Write-Host "  SLACK_TEAM_ID/SLACK_BOT_TOKEN: $(if (([Environment]::GetEnvironmentVariable('SLACK_TEAM_ID','User')) -and ([Environment]::GetEnvironmentVariable('SLACK_BOT_TOKEN','User'))) { '✓ 주입됨 (slack MCP용)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"
Write-Host "  TYPESAFE_API_KEY: $(if ([Environment]::GetEnvironmentVariable('TYPESAFE_API_KEY','User')) { '✓ 주입됨 (TypeSafe Jev SDK용)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"
Write-Host "  OPENAI_API_KEY: $(if ([Environment]::GetEnvironmentVariable('OPENAI_API_KEY','User')) { '✓ 주입됨 (OpenAI SDK용)' } else { '❌ 미주입 (.\win-setup.ps1 -EnvOnly 재실행)' })"

# ------------------------------------------------------------
# 완료 안내 — 사람이 직접 해야만 하는 일만 남긴다
#   맥 스크립트의 "✅ 완료! 다음 단계:" 와 같은 자리. 자동화할 수 없는 것
#   (계정 로그인, OS 재부팅, 앱 최초 실행)만 번호를 매겨 적는다.
# ------------------------------------------------------------
Write-Host ''
Write-Host '✅ 완료! 다음 단계:' -ForegroundColor Green
Write-Host '  1. 지금 열려 있는 창을 닫고 새 PowerShell 창(pwsh)을 여세요'
Write-Host '     ↳ 윈도우는 이미 열린 창의 PATH·환경변수를 갱신하지 않습니다. 새 창을 열어야 방금 깐 명령과 팀 공용 토큰이 전부 잡힙니다'
Write-Host '  2. 개발자 모드·긴 경로 허용을 켰다면 한 번 재부팅해 주세요'
Write-Host '     ↳ 이 두 가지는 재부팅 후에 유효해집니다. 켜지 않으면 Flutter 빌드가 심볼릭 링크/경로 길이 오류로 실패합니다'
Write-Host '     ↳ 위 검증에서 ❌ 로 나왔다면: 관리자 PowerShell에서  .\win-setup.ps1 -SystemOnly'
Write-Host '  3. Android Studio를 한 번 실행해 최초 실행 화면을 넘긴 뒤: flutter doctor'
Write-Host '     ↳ SDK·NDK·AVD는 이미 자동으로 설치·구성했습니다. Windows 데스크톱 앱까지 빌드하려면 Visual Studio Build Tools 항목이 ✓ 여야 합니다'
Write-Host '  4. AI 코딩 CLI 최초 1회 로그인'
Write-Host '     ↳ claude (Anthropic 계정) · codex (ChatGPT 계정) · agy (Google 계정) · slack login (Slack 워크스페이스)'
Write-Host '  5. Claude Code에서 /mcp 실행 → figma·mobbin OAuth 로그인 (최초 1회, Mobbin 유료 플랜 필요)'
Write-Host '     ↳ OpenCode도 재시작한 뒤 /connect로 모델 계정 연결, opencode mcp auth figma · opencode mcp auth mobbin 실행'
Write-Host '     ↳ claude mcp list · opencode mcp list 로 기본 MCP 10개의 실제 연결을 확인하세요'
Write-Host '     ↳ zenhub·jira·slack은 OAuth 로그인이 필요 없습니다 — 아래 6번의 1Password 팀 공용 토큰으로 인증합니다'
Write-Host '     ↳ atlassian(Jira) MCP는 Docker로 뜹니다. Docker Desktop을 먼저 실행해 두세요'
Write-Host '  6. 토큰이 ❌ 미주입으로 나왔다면 1Password CLI 통합을 켜고 다시 주입하세요'
Write-Host '     ↳ 1Password 앱 로그인(team-cocodeinc) → 설정 > 보안 > Windows Hello 켜기 → 설정 > 개발자 > "1Password CLI와 통합" 체크'
Write-Host '       (맥은 Touch ID였지만 윈도우는 Windows Hello 입니다 — 이걸 먼저 켜야 개발자 탭의 통합 옵션이 동작합니다)'
Write-Host '       확인: op account list 에 팀 계정이 보이면 성공 → 그 뒤  .\win-setup.ps1 -EnvOnly'
Write-Host '  7. GitHub 인증(gh)이 ❌ 이면 cocode-skills·cob(co-bricks) 둘 다 설치되지 않습니다'
Write-Host '     ↳ 자동 로그인은 팀 "API Token" 볼트 > "GitHub API Token" > credential 필드에서 읽어 처리됩니다'
Write-Host '     ↳ 안 되면 수동으로: gh auth login → 그 뒤  .\win-setup.ps1 -DartOnly (cob만 다시 깔면 되는 경우)'
Write-Host '  8. lefthook(Git 훅)은 레포마다 한 번씩 켜야 합니다 — lefthook.yml 이 있는 프로젝트 폴더에서: lefthook install'
Write-Host '  9. Tailscale·Slack·Figma·Claude Desktop은 각각 처음 실행할 때 팀 계정으로 로그인해 주세요'
Write-Host ' 10. 프롬프트 아이콘이 □ 로 보이면 터미널 폰트가 아직 안 바뀐 것입니다'
Write-Host "     ↳ Windows Terminal 설정 > 기본값 > 모양 > 글꼴에서 '$CocodeFontFace' 선택 (이 스크립트가 자동 적용을 시도하지만, 터미널이 실행 중이면 덮어써질 수 있습니다)"
Write-Host ' 11. TrafficMonitor(작업표시줄 시스템 모니터)는 최초 1회 직접 실행해야 화면에 나타납니다 — 시작 메뉴에서 TrafficMonitor 실행'
Write-Host '     ↳ 실행한 뒤 트레이 아이콘을 마우스 오른쪽 클릭 > 설정에서 "부팅 시 자동 시작"을 켜 두면 다음부터는 자동으로 떠 있습니다'
Write-Host ''
Write-Host '   레포를 둘 곳: 경로가 길면 Gradle·Flutter 빌드가 깨질 수 있습니다 — C:\src 처럼 짧은 폴더를 권장합니다' -ForegroundColor DarkGray

}


# ------------------------------------------------------------
# 모드 실행 마무리 안내
#   전체 설치가 아닐 때는 위의 긴 검증 대신 그 모드에 맞는 한 줄만 남긴다.
# ------------------------------------------------------------
if ($EnvOnly) {
    Write-Host ''
    # 맥(--env-only)과 같이 '무엇이 들어갔는지'를 먼저 요약한다. 값은 찍지 않고 있고/없고만 본다.
    Write-Host '── 팀 공용 토큰 주입 결과 ────────────────────' -ForegroundColor DarkCyan
    $eoZh    = [Environment]::GetEnvironmentVariable('ZENHUB_API_TOKEN','User')
    $eoJira  = [Environment]::GetEnvironmentVariable('JIRA_API_TOKEN','User')
    $eoSlang = [Environment]::GetEnvironmentVariable('SLANG_GPT_API_KEY','User')
    $eoDcmE  = [Environment]::GetEnvironmentVariable('DCM_EMAIL','User')
    $eoDcmK  = [Environment]::GetEnvironmentVariable('DCM_CI_KEY','User')
    $eoSlkT  = [Environment]::GetEnvironmentVariable('SLACK_TEAM_ID','User')
    $eoSlkB  = [Environment]::GetEnvironmentVariable('SLACK_BOT_TOKEN','User')
    $eoTs    = [Environment]::GetEnvironmentVariable('TYPESAFE_API_KEY','User')
    $eoOai   = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY','User')
    Write-Host ("  ZENHUB_API_TOKEN             : " + $(if ($eoZh)    { '✓ 주입됨' } else { '❌ 미주입' }))
    Write-Host ("  JIRA_API_TOKEN               : " + $(if ($eoJira)  { '✓ 주입됨' } else { '❌ 미주입' }))
    Write-Host ("  SLANG_GPT_API_KEY            : " + $(if ($eoSlang) { '✓ 주입됨' } else { '❌ 미주입' }))
    Write-Host ("  DCM_EMAIL/DCM_CI_KEY         : " + $(if ($eoDcmE -and $eoDcmK) { '✓ 주입됨' } else { '❌ 미주입' }))
    Write-Host ("  SLACK_TEAM_ID/SLACK_BOT_TOKEN: " + $(if ($eoSlkT -and $eoSlkB) { '✓ 주입됨' } else { '❌ 미주입' }))
    Write-Host ("  TYPESAFE_API_KEY             : " + $(if ($eoTs)    { '✓ 주입됨' } else { '❌ 미주입' }))
    Write-Host ("  OPENAI_API_KEY               : " + $(if ($eoOai)   { '✓ 주입됨' } else { '❌ 미주입' }))

    $eoMissing = @()
    if (-not $eoZh)    { $eoMissing += 'ZENHUB_API_TOKEN' }
    if (-not $eoJira)  { $eoMissing += 'JIRA_API_TOKEN' }
    if (-not $eoSlang) { $eoMissing += 'SLANG_GPT_API_KEY' }
    if (-not ($eoDcmE -and $eoDcmK)) { $eoMissing += 'DCM_EMAIL/DCM_CI_KEY' }
    if (-not ($eoSlkT -and $eoSlkB)) { $eoMissing += 'SLACK_TEAM_ID/SLACK_BOT_TOKEN' }
    if (-not $eoTs)    { $eoMissing += 'TYPESAFE_API_KEY' }
    if (-not $eoOai)   { $eoMissing += 'OPENAI_API_KEY' }

    Write-Host ''
    if ($eoMissing.Count -eq 0) {
        Write-Host '✅ 토큰 주입 단계 완료 (전체 설치는 옵션 없이 .\win-setup.ps1 실행)' -ForegroundColor Green
        Write-Host '   ↳ 주입된 값은 지금 열려 있는 창에는 반영되지 않습니다 — 새 PowerShell 창을 열어 claude 를 실행하세요'
    } else {
        # 하나라도 못 넣었으면 초록색 '완료' 대신 다음에 할 일을 알려 준다 (맥 --env-only 와 같은 원칙).
        Write-Host ("⚠ 아직 주입되지 않은 토큰이 있습니다: " + ($eoMissing -join ', ')) -ForegroundColor Yellow
        Write-Host '   ↳ 1Password 앱 로그인 → 설정 > 보안 > "Windows Hello로 잠금 해제" 켜기 → 설정 > 개발자 > "1Password CLI와 통합" 체크'
        Write-Host '   ↳ 확인:  op account list   ← 팀 계정이 보이면 성공'
        Write-Host '   ↳ 그 뒤 다시 실행:  .\win-setup.ps1 -EnvOnly'
        Write-Host '   ↳ 계정은 보이는데 계속 실패하면 팀 관리자에게 "API Token" 금고 공유를 요청해 주세요'
    }
}
if ($DartOnly) {
    Write-Host ''
    # 맥(--dart-only)과 같이 패키지별로 다시 확인한다 — 하나라도 빠졌으면 초록색 '완료'를 찍지 않는다.
    $doList = $(if (Test-Cmd 'dart') { ((& dart pub global list 2>$null) | Out-String) } else { '' })
    $doNames = @('coverage','melos','mason_cli','flutter_gen','jaspr_cli','serverpod_cli','flutterfire_cli','marionette_mcp','mcp_server_dart')
    $doMissing = @($doNames | Where-Object { $doList -notmatch ('(?m)^' + [regex]::Escape($_) + ' ') })
    $doCob = ($doList -match '(?m)^(cob|co_bricks) ')
    Write-Host ("  dart 글로벌 패키지: " + $(if ($doMissing.Count -eq 0) { '✓ ' + ($doNames -join ', ') } else { '❌ 누락: ' + ($doMissing -join ', ') }))
    Write-Host ("  cob(co-bricks)   : " + $(if ($doCob) { '✓ 설치됨' } else { '❌ 없음' }))
    Write-Host ''
    if (($doMissing.Count -eq 0) -and $doCob) {
        Write-Host '✅ Dart 글로벌 패키지 처리 완료 (전체 설치는 옵션 없이 .\win-setup.ps1 실행)' -ForegroundColor Green
        Write-Host '   ↳ 방금 깔린 명령들은 %LOCALAPPDATA%\Pub\Cache\bin 에 있습니다 — 새 터미널에서 바로 쓸 수 있습니다'
    } else {
        $doLeft = @($doMissing)
        if (-not $doCob) { $doLeft += 'cob(co-bricks)' }
        Write-Host ("⚠ 설치되지 않은 패키지가 있습니다: " + ($doLeft -join ', ')) -ForegroundColor Yellow
        Write-Host '   ↳ 위 ⚠ 메시지와 네트워크 상태를 확인한 뒤 다시 실행해 주세요:  .\win-setup.ps1 -DartOnly'
        Write-Host '   ↳ cob(co-bricks)이 빠졌다면 GitHub 인증이 필요합니다:  gh auth login  →  gh auth setup-git  →  .\win-setup.ps1 -DartOnly'
    }
}
if ($SystemOnly) {
    Write-Host ''
    Write-Host '✅ 윈도우 시스템 설정 점검 완료 (전체 설치는 옵션 없이 .\win-setup.ps1 실행)' -ForegroundColor Green
    Write-Host '   ↳ 개발자 모드·긴 경로 허용은 재부팅 후에 유효해집니다'
}
