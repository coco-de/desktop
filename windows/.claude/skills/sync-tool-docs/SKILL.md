---
name: sync-tool-docs
description: win-setup.ps1에서 도구(GUI 앱·CLI·Dart 패키지·MCP/플러그인 등)를 추가하거나 삭제할 때 README.md와 스크립트 내 관련 문구를 빠짐없이 함께 업데이트한다. Install-Winget/Install-Scoop/dart pub global/MCP 등록 등 설치 항목을 변경하는 모든 작업에서 반드시 사용.
---

# sync-tool-docs — 도구 추가/삭제 시 문서 동기화

이 레포는 `win-setup.ps1` 하나로 팀 전체 윈도우 개발환경을 세팅하고, `README.md`가 그 내용을 사람이 읽는 문서로 그대로 반영한다.
**도구를 하나라도 추가/삭제/버전 변경하면 아래 체크리스트의 모든 지점을 함께 갱신해야 한다.** 하나라도 빠지면 스크립트와 문서가 어긋난다.

## 0. 시작하기 전 — 형제 레포 확인

이 레포에는 짝이 있다: **[coco-de/co-mac](https://github.com/coco-de/co-mac)** (`mac-setup.sh`).

- [ ] **추가하려는 도구가 맥에도 있어야 하는가?** 팀 표준 도구라면 co-mac에도 같이 추가해야 한다. 윈도우에만 필요한 도구(Visual Studio Build Tools 등)라면 그렇게 판단한 근거를 남긴다.
- [ ] **맥에 있는데 윈도우에 없는 것을 추가하는 중인가?** README `🍎 맥과 무엇이 다른가요`의 "빠진 것" 표에서 해당 행을 지운다.
- [ ] **윈도우에서 불가능해 제외하는가?** 같은 표의 "빠진 것" 또는 "일부러 하지 않은 것"에 이유와 대체 수단을 적는다. 조용히 빼면 안 된다.

## 1. win-setup.ps1 내부 동기화 지점

설치 코드 자체 외에, 스크립트 안에 도구 이름이 열거된 곳들:

- [ ] **해당 섹션의 `Write-Step "..."` 메시지** — 도구 목록을 나열함 (예: 1단계 GUI 앱 목록, 2.5단계 MCP 목록, 3단계 CLI 도구 목록)
- [ ] **섹션 상단 주석 블록** — 도구/계층 구조와 "왜 이렇게 하는지"를 설명하는 주석
- [ ] **파일 상단 '실행 단계 맵' 주석** — 단계 목록에 도구 이름이 들어가 있으면 함께 갱신
- [ ] **`Show-Usage` 함수** — `-DartOnly` 설명처럼 옵션 도움말에 패키지 이름이 나열된 곳
- [ ] **10단계 `설치 검증` 출력** — 주요 도구라면 검증 줄 추가/삭제. 검증 줄은 반드시 `❌`일 때 **직접 복붙할 수 있는 수동 설치 명령**을 함께 적는다
- [ ] **마지막 `✅ 완료! 다음 단계` 안내** — 수동 후속 단계(로그인, 인증, 최초 1회 실행 등)가 필요한 도구라면 안내 번호 추가/삭제 및 번호 재정렬

## 2. README.md 동기화 지점

- [ ] **🧰 우리 팀의 기술 스택** (`<a id="tech-stack">`) — 해당 분류 테이블(패키지 관리자 / GUI 앱 / CLI 도구 / Flutter·Dart / 클라우드·런타임 / 터미널 환경)에 셀 추가/삭제
  - GUI 앱 테이블은 5열, CLI 도구 테이블은 6열 그리드 — 행이 넘치면 새 `<tr>` 추가, 빈 자리는 빈 `<td>`로 채움
  - 삭제 시 빈 `<td>`로 남기지 말고 뒤 셀을 당겨 정렬
- [ ] **아이콘** (`assets/icons/`) — 도구를 추가하면 **항상 실제 아이콘을 내려받아 반영한다.** 텍스트-only는 어떤 소스로도 못 구할 때의 최후 수단이며, "귀찮아서" 텍스트로 두지 않는다. 획득 순서(위에서부터 성공하는 것을 채택):
  1. **Simple Icons SVG** (선호) — `curl -fsSL https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/<slug>.svg`
     - 기존 파일 형식에 맞춘다: 단색 `<path>` + 브랜드색 `fill="#hex"` + `<title>`
     - Dart 생태계 도구는 `dart.svg` 재사용 관례 · 마이크로소프트 제품은 `winget.png`(MS 로고) 재사용 가능
  2. **실제 브랜드/앱 아이콘 PNG** — Simple Icons에 없을 때. 안정적 소스:
     - Google 파비콘 서비스: `curl -fsSL "https://www.google.com/s2/favicons?domain=<도메인>&sz=128" -o assets/icons/<name>.png`
     - 또는 공식 저장소의 배포 자산(예: PowerShell은 `PowerShell/PowerShell` 레포의 `assets/`)
     - 128px 이상 정사각으로 저장 → `sips -g pixelWidth`(맥) 로 크기 확인 → **실제로 열어(Read) 올바른 로고인지 눈으로 확인**
     - SVG를 받았다면 `viewBox`가 정사각인지 확인한다. 아니면 위아래 여백을 넣어 정사각으로 맞춘다(36×36 셀에서 찌그러지지 않게)
  3. (1·2 모두 실패했을 때만) 텍스트 표기
  - 저장한 아이콘은 README `<img src="assets/icons/…">` 셀 **양쪽**(🧰 기술 스택 표 + 도구별 상세 표)에서 참조한다 (기술 스택은 36px, 상세 표는 20px)
  - 삭제: 다른 곳에서 안 쓰는 아이콘 파일이면 `assets/icons/`에서도 제거
  - 기술 스택 섹션 하단 `<sub>※ ...</sub>` **각주**(아이콘 출처 목록)도 함께 갱신
- [ ] **📦 무엇이 설치되나요** (`<a id="whats-installed">`) — 요약 테이블의 해당 분류 행에서 도구 이름 추가/삭제
- [ ] **도구별 상세 설명 펼쳐보기** (`<details>`) — 해당 분류 표에 `| 아이콘 | 도구 | 용도 |` 행 추가/삭제
  - 용도는 비개발자도 이해할 수 있는 한 줄 설명 + **정확한 winget/Scoop 패키지 ID**
  - 관리자 권한이 필요하거나 ARM64에서 안 되는 항목은 `⚠` 로 표시
- [ ] **🍎 맥과 무엇이 다른가요** (`<a id="vs-mac">`) — 대체/제외/의도적 미실행 표에 영향이 있으면 갱신
- [ ] **✅ 설치 후 확인할 것** (`<a id="after-install">`) — 검증 출력 예시 코드 블록, 수동 후속 단계 목록에 영향이 있으면 갱신
- [ ] **🐛 문제가 생겼나요** — 그 도구에 알려진 윈도우 특유의 함정이 있으면 `<details>` 항목 추가
- [ ] 새 분류가 생기면 목차·섹션 구조도 함께 확장

## 3. 완료 전 검증

### 3-1. 문법 검사 (필수)

PowerShell 문법 오류는 눈으로 잡히지 않는다. 반드시 파서로 확인한다.

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/work" mcr.microsoft.com/powershell:latest \
  pwsh -NoProfile -c "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('/work/win-setup.ps1',[ref]\$null,[ref]\$e); if(\$e){\$e|%{ '{0}: {1}' -f \$_.Extent.StartLineNumber, \$_.Message }}else{'PARSE OK'}"
```

윈도우에서 작업 중이라면:

```powershell
$e = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\win-setup.ps1), [ref]$null, [ref]$e)
if ($e) { $e } else { 'PARSE OK' }
```

특히 자주 나는 오류:
- 큰따옴표 문자열 안에서 `\"` 로 따옴표를 escape 하려 함 → PowerShell은 백틱(`` ` ``)이 escape 문자다. 작은따옴표로 바꾸는 게 가장 안전하다
- 5.1에서 파싱되지 않는 문법(`? :`, `??`, `&&`, `||`) 사용

### 3-2. 인코딩 검사 (필수)

```bash
head -c 3 win-setup.ps1 | xxd | head -1   # efbbbf 로 시작해야 한다 (UTF-8 BOM)
```

BOM이 사라졌으면 Windows PowerShell 5.1에서 한글이 전부 깨진다.

### 3-3. 양방향 교차 확인

작업을 마치기 전에 도구 이름으로 확인한다:

```bash
grep -in "<도구이름>" win-setup.ps1 README.md
```

- **추가**: 스크립트(설치 코드 + Write-Step/주석/검증)와 README(기술 스택 + 요약 테이블 + 상세 설명)에 모두 등장하는지
- **삭제**: 두 파일 어디에도 잔존 언급이 없는지 (아이콘 파일 잔존 포함 — `ls assets/icons/`)
- **패키지 ID**: README에 적은 winget ID가 스크립트의 `Install-Winget -Id` 값과 **글자 단위로 같은지**

## 스타일 관례

- 문서·주석·로그 메시지는 모두 **한국어**, 비개발자 팀원도 읽는 문서임을 감안해 친절한 설명 유지
- 스크립트의 멱등성 패턴 유지: 설치 전 존재 확인(`Write-Ok "... 이미 설치됨"`), 실패 시 `Write-Warn "... → 건너뜀 (수동 설치: ...)"`
- 새 헬퍼 함수를 만들지 말고 기존 공통 헬퍼(`Install-Winget`·`Install-Scoop`·`Add-UserPath`·`Set-UserEnv`)를 쓴다. 그 섹션에서만 쓰는 지역 헬퍼는 허용
- 커밋 메시지는 기존 관례(gitmoji + 한국어, 예: `feat: ✨ win-setup.ps1 GUI 앱 설치에 Zed 추가`)를 따름
