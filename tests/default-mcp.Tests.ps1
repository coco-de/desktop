# 실행: pwsh -NoProfile -File tests/default-mcp.Tests.ps1
# 전체 설치를 실행하지 않고 임시 홈에서 6.6단계의 실제 병합 코드만 검증합니다.
param([string]$SetupScript = (Join-Path $PSScriptRoot '../windows/win-setup.ps1'))
$ErrorActionPreference = 'Stop'
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($SetupScript, [ref]$null, [ref]$errors) | Out-Null
if ($errors) { throw ($errors | Out-String) }
$source = [IO.File]::ReadAllText((Resolve-Path $SetupScript))
$start = $source.IndexOf('Write-Step "6.6. OpenCode CLI')
$end = $source.IndexOf('# 7. PowerShell 프로필', $start)
$block = $source.Substring($start, $end - $start)
$originalHome = $env:USERPROFILE
$originalXdg = $env:XDG_CONFIG_HOME
$testHome = Join-Path ([IO.Path]::GetTempPath()) ('mcp-test-' + [Guid]::NewGuid().ToString('N'))
function Test-Cmd { return $true }
function Write-Step { }
function Write-Ok { }
function Write-Info { }
function Write-Warn { param($Message); $script:Warnings += @($Message) }
function Assert-True { param($Value, $Message); if (-not $Value) { throw $Message } }
try {
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null
    $env:USERPROFILE = $testHome
    $env:XDG_CONFIG_HOME = Join-Path $testHome '별도 config'
    $script:Warnings = @()
    Invoke-Expression $block
    Assert-True ($Warnings.Count -eq 0) '새 설정 등록 중 경고 발생'
    $claudePath = Join-Path $testHome '.claude.json'
    $opencodePath = Join-Path $env:XDG_CONFIG_HOME 'opencode/opencode.json'
    $claude = [IO.File]::ReadAllText($claudePath) | ConvertFrom-Json
    $opencode = [IO.File]::ReadAllText($opencodePath) | ConvertFrom-Json
    $names = @('cob','dart','figma','marionette','atlassian','mobbin','slack','zenhub','chrome-devtools','playwright')
    foreach ($name in $names) {
        Assert-True ($null -ne $claude.mcpServers.$name) "Claude MCP 누락: $name"
        Assert-True ($opencode.mcp.$name.enabled) "OpenCode MCP 누락: $name"
    }
    Assert-True ($claude.mcpServers.'chrome-devtools'.command -eq 'cmd') 'npx Windows 래핑 누락'
    Assert-True (($opencode.mcp.dart.command -join ' ') -eq 'cmd /c dart mcp-server') 'dart Windows 래핑 누락'
    Assert-True ($opencode.mcp.atlassian.environment.JIRA_API_TOKEN -ceq '{env:JIRA_API_TOKEN}') 'OpenCode 토큰 참조 손상'
    Assert-True ($claude.mcpServers.atlassian.env.JIRA_API_TOKEN -ceq '${JIRA_API_TOKEN}') 'Claude 토큰 참조 손상'
    Assert-True ($opencode.mcp.zenhub.headers.Authorization -ceq '{env:ZENHUB_API_TOKEN}') 'ZenHub 헤더 손상'
    Assert-True ($opencode.mcp.zenhub.oauth -eq $false) 'ZenHub 토큰 인증 설정 누락'

    # 계정 정보와 개인 MCP를 보존하면서 팀의 예전 Docker 이름만 정리해야 합니다.
    $original = '{"account":"keep-me","mcpServers":{"personal":{"command":"user-server","args":[]},"mcp-atlassian":{"command":"docker","args":["run","ghcr.io/sooperset/mcp-atlassian:latest"]}}}'
    [IO.File]::WriteAllText($claudePath, $original)
    Invoke-Expression $block
    $claude = [IO.File]::ReadAllText($claudePath) | ConvertFrom-Json
    Assert-True ($claude.account -eq 'keep-me') '기존 계정 정보 손상'
    Assert-True ($claude.mcpServers.personal.command -eq 'user-server') '개인 MCP 손상'
    Assert-True ($null -eq $claude.mcpServers.'mcp-atlassian') '예전 팀 Docker 등록 중복'
    $before = [IO.File]::ReadAllText($claudePath)
    $backup = [IO.File]::ReadAllText($claudePath + '.bak')
    Invoke-Expression $block
    Assert-True ([IO.File]::ReadAllText($claudePath) -ceq $before) '재실행 시 설정 변화'
    Assert-True ([IO.File]::ReadAllText($claudePath + '.bak') -ceq $backup) '최초 백업 덮어씀'

    # 한 클라이언트의 설정 오류가 다른 클라이언트 등록을 막으면 안 됩니다.
    foreach ($invalid in @('{broken', '[]', '{"mcpServers":[]}')) {
        [IO.File]::WriteAllText($claudePath, $invalid)
        Remove-Item -LiteralPath $opencodePath -Force
        Invoke-Expression $block
        Assert-True ([IO.File]::ReadAllText($claudePath) -ceq $invalid) '잘못된 원본 설정 덮어씀'
        Assert-True (Test-Path -LiteralPath $opencodePath) '다른 클라이언트 등록 중단'
    }
    Write-Host 'PASS: Windows 문법 · MCP 10개 · cmd 래핑 · 토큰 참조 · 설정 보존 · 멱등성 · 오류 격리'
} finally {
    $env:USERPROFILE = $originalHome
    $env:XDG_CONFIG_HOME = $originalXdg
    Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
}
