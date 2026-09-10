---
name: sync-tool-docs
description: macos/mac-setup.sh, windows/win-setup.ps1, linux/linux-setup.sh 에서 도구(GUI 앱·CLI·Dart 패키지·MCP/플러그인 등)를 추가하거나 삭제할 때 해당 README.md와 스크립트 내 관련 문구를 빠짐없이 함께 업데이트한다. 설치 항목을 변경하는 모든 작업에서 반드시 사용.
---

# sync-tool-docs — 도구 추가/삭제 시 문서 동기화

이 저장소는 OS별 스크립트(`macos/mac-setup.sh` · `windows/win-setup.ps1` · `linux/linux-setup.sh`)로 팀 전체 개발환경을 세팅하고, 각 폴더의 `README.md`가 그 내용을 사람이 읽는 문서로 그대로 반영한다.
**도구를 하나라도 추가/삭제/버전 변경하면 아래 체크리스트의 모든 지점을 함께 갱신해야 한다.** 하나라도 빠지면 스크립트와 문서가 어긋난다.

## 0. 시작하기 전 — 세 플랫폼 확인

팀 표준 도구가 바뀌면 **macos · windows · linux 를 함께** 갱신한다.

- [ ] **추가하려는 도구가 세 OS 모두에 있어야 하는가?** 팀 표준이면 셋 다 추가한다. 한 OS에만 필요한 도구(Xcode, Visual Studio Build Tools, KVM 등)라면 그렇게 판단한 근거를 README `🍎 맥과 무엇이 다른가요`에 남긴다.
- [ ] **한쪽에 있는데 다른 쪽에 없는 것을 추가하는 중인가?** 해당 README의 "빠진 것" 표에서 그 행을 지운다.
- [ ] **그 OS에서 불가능해 제외하는가?** 같은 표의 "빠진 것" 또는 "일부러 하지 않은 것"에 이유와 대체 수단을 적는다. 조용히 빼면 안 된다.

작업 폴더 기준으로 아래 해당 섹션만 이어서 수행한다. 경로도 그 폴더 기준이다.

---

## macOS — `macos/mac-setup.sh` + `macos/README.md`

### 1. 스크립트 내부 동기화 지점

- [ ] **해당 섹션의 `log "..."` 메시지** — 도구 목록을 나열함
- [ ] **섹션 상단 주석** — 도구/계층 구조를 설명하는 주석 블록 (특히 2.5단계 MCP 3계층 주석)
- [ ] **9단계 `설치 검증` 출력** — 주요 도구라면 검증 echo 라인 추가/삭제
- [ ] **마지막 `✅ 완료! 다음 단계` 안내** — 수동 후속 단계가 필요하면 안내 번호 추가/삭제 및 번호 재정렬

### 2. README.md 동기화 지점

- [ ] **🧰 우리 팀의 기술 스택** — GUI 앱 테이블은 5열, CLI 도구 테이블은 6열. 삭제 시 빈 `<td>`로 남기지 말고 뒤 셀을 당겨 정렬
- [ ] **아이콘** (`macos/assets/icons/`) — 아래 [아이콘 규칙](#icons) 준수. 기술 스택은 36px, 상세 표는 20px
- [ ] **📦 무엇이 설치되나요** — 요약 테이블의 해당 분류 행
- [ ] **도구별 상세 설명 펼쳐보기** — `| 아이콘 | 도구 | 용도 |` 행 (비개발자도 이해할 한 줄)
- [ ] **✅ 설치 후 확인할 것** — 검증 출력 예시, 수동 후속 단계

### 3. 완료 전 검증

```bash
grep -in "<도구이름>" macos/mac-setup.sh macos/README.md
```

---

## Windows — `windows/win-setup.ps1` + `windows/README.md`

### 1. 스크립트 내부 동기화 지점

- [ ] **해당 섹션의 `Write-Step "..."` 메시지**
- [ ] **섹션 상단 주석 블록** · **파일 상단 '실행 단계 맵' 주석**
- [ ] **`Show-Usage` 함수** — 옵션 도움말에 패키지 이름이 나열된 곳
- [ ] **10단계 `설치 검증` 출력** — `❌`일 때 **직접 복붙할 수 있는 수동 설치 명령**을 함께 적는다
- [ ] **마지막 `✅ 완료! 다음 단계` 안내**

### 2. README.md 동기화 지점

macOS와 동일한 표·아이콘·상세 설명 항목. 추가로:

- [ ] 용도에 **정확한 winget/Scoop 패키지 ID**. 관리자 권한 또는 ARM64 불가 항목은 `⚠`
- [ ] **🍎 맥과 무엇이 다른가요** · **🐛 문제가 생겼나요** (윈도우 고유 함정)

### 3. 완료 전 검증

문법 오류는 눈으로 잡히지 않는다. 반드시 파서로 확인한다.

```bash
docker run --rm --platform linux/amd64 -v "$PWD/windows:/work" mcr.microsoft.com/powershell:latest \
  pwsh -NoProfile -c "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('/work/win-setup.ps1',[ref]\$null,[ref]\$e); if(\$e){\$e|%{ '{0}: {1}' -f \$_.Extent.StartLineNumber, \$_.Message }}else{'PARSE OK'}"
```

```bash
head -c 3 windows/win-setup.ps1 | xxd | head -1   # efbbbf 로 시작해야 한다 (UTF-8 BOM)
grep -in "<도구이름>" windows/win-setup.ps1 windows/README.md
```

README의 winget ID가 스크립트의 `Install-Winget -Id` 값과 **글자 단위로 같은지** 확인한다.

자주 나는 오류: 큰따옴표 안 `\"` (PowerShell escape는 백틱), 5.1에서 파싱 안 되는 `? :` · `??` · `&&` · `||`.

---

## Linux — `linux/linux-setup.sh` + `linux/README.md`

### 1. 스크립트 내부 동기화 지점

- [ ] **해당 섹션의 `log "..."` 메시지**
- [ ] **섹션 상단 주석 블록** · **파일 상단 '설치 단계 개요' 주석**
- [ ] **`usage()` 함수**
- [ ] **10단계 `설치 검증` 출력** — `❌`일 때 복붙 가능한 수동 설치 명령
- [ ] **마지막 `✅ 완료! 다음 단계` 안내**

### 2. README.md 동기화 지점

macOS와 동일한 표·아이콘·상세 설명 항목. 추가로:

- [ ] 용도에 **정확한 apt 패키지명 / snap 이름 / 저장소 URL**. sudo 또는 ARM64 불가 항목은 `⚠`
- [ ] **🍎 맥과 무엇이 다른가요** · **🐛 문제가 생겼나요** (리눅스 고유 함정)

### 3. 완료 전 검증

```bash
bash -n linux/linux-setup.sh
shellcheck -S warning linux/linux-setup.sh
file linux/linux-setup.sh          # CRLF 금지
head -c 3 linux/linux-setup.sh | xxd | head -1   # BOM(efbbbf) 금지
grep -in "<도구이름>" linux/linux-setup.sh linux/README.md
```

README의 apt/snap 이름이 스크립트의 `apt_install`·`snap_install` 인자와 **글자 단위로 같은지** 확인한다.

자주 나는 오류: `set -e` 하에서 실패 가능한 명령을 `||` 없이 둠, BOM/CRLF 로 shebang 깨짐.

---

<a id="icons"></a>

## 아이콘 규칙

도구를 추가하면 **항상 실제 아이콘을 내려받아 반영한다.** 텍스트-only는 어떤 소스로도 못 구할 때의 최후 수단이다.

1. **Simple Icons SVG** (선호) — `curl -fsSL https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/<slug>.svg`
   - 단색 `<path>` + 브랜드색 `fill="#hex"` + `<title>`
   - Dart 생태계는 `dart.svg` 재사용
2. **실제 브랜드/앱 아이콘 PNG** — Google 파비콘 `sz=128` 또는 공식 자산. 128px 이상 정사각. **실제로 열어(Read) 올바른 로고인지 확인**
3. (1·2 모두 실패했을 때만) 텍스트 표기

저장 위치는 해당 플랫폼의 `assets/icons/`. 기술 스택 섹션 하단 각주도 함께 갱신한다. 삭제 시 다른 곳에서 안 쓰면 아이콘 파일도 제거한다.

## 스타일 관례

- 문서·주석·로그 메시지는 모두 **한국어**, 비개발자 팀원도 읽는 문서임을 감안해 친절한 설명 유지
- 스크립트의 멱등성 패턴 유지: 설치 전 존재 확인, 실패 시 경고 후 건너뜀
- 새 헬퍼를 만들지 말고 각 스크립트 상단의 공통 헬퍼만 쓴다
- 커밋 메시지는 기존 관례(gitmoji + 한국어, 예: `feat: ✨ mac-setup.sh GUI 앱 설치에 Zed 추가`)를 따름
