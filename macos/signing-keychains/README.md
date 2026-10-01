# 서명 키체인 로그인 자동 해제

macOS에서 앱·설치 패키지를 서명할 때 키체인 암호를 반복해서 묻는 문제를 설정합니다.
**선택형**이며, 전체 개발환경 설치만 실행하면 활성화되지 않습니다.

## 구조

1. 암호 원본은 **1Password**에 보관합니다. 이 Mac의 실제 키체인 암호와 같은 값이어야 합니다.
2. 최초 등록·갱신 때만 `op`로 읽어 **login 키체인에 암호화 보관**합니다.
3. 캐시 복호화 ACL에는 **서명된 전용 helper 하나만** 넣습니다. 모든 앱 허용을 사용하지 않습니다.
4. 로그인 LaunchAgent가 helper를 실행해 대상 키체인을 엽니다. 이때는 `op`·1Password 승인·암호 입력 창을 호출하지 않습니다.

암호는 `Security.framework` API에 메모리로 전달합니다. 명령행 `-p`/`-k`, 로그, `.zshrc`, plist, 평문 임시 파일에는 넣지 않습니다. helper의 core dump도 끕니다. 설정 JSON에는 키체인 경로·원본 참조·서명 정보만 저장합니다.

`login` 키체인은 일반적인 사용자 로그인 때 자동으로 열려야 합니다. Mac 로그인 암호와 login 키체인 암호가 어긋나거나 login이 별도로 잠긴 경우에는 시스템에서 먼저 열어야 합니다. 로그인 전에 실행되는 시스템 데몬용 설정은 아닙니다. 로그인 직후 타이밍 문제는 5분 간격으로 재확인하며, UI 요청을 반복하지 않습니다.

## 준비

- Xcode 명령줄 도구와 Python 3 (`/usr/bin/python3`)
- 1Password 앱·CLI(`op`) 및 해당 원본 항목에 접근할 계정
- 1Password 앱 > 설정 > 개발자 > **1Password CLI와 통합**
- 1Password에서 암호 필드의 **비밀 참조 복사**로 얻은 `op://볼트/항목/필드`

암호가 Mac마다 다르면 1Password 항목도 Mac별로 나눕니다. 계정 암호가 아닌 **해당 파일 키체인의 암호**를 저장하세요. 초기 등록 때 1Password 승인이 필요할 수 있고, 서명 키 ACL을 처음 보완할 때 macOS 인증 창이 뜰 수 있습니다.

## 등록

저장소 루트에서 실행하는 예시입니다. 아래 `op://`는 예시이므로 실제 참조로 바꿉니다.

```bash
bash macos/mac-setup.sh --keychains-only install \
  --laputa-ref 'op://개발환경/이 Mac/laputa' \
  --fastlane-ref 'op://개발환경/이 Mac/fastlane_tmp' \
  --account 'team-cocodeinc.1password.com'
```

`security list-keychains -d user`의 **실제 경로**를 탐색합니다. 이름이 다르거나 같은 이름이 여러 개면 다음 옵션으로 지정합니다.

```bash
--laputa-keychain "$HOME/Library/Keychains/company-signing.keychain-db"
--fastlane-keychain "$HOME/Library/Keychains/build-temp.keychain-db"
```

실제 fastlane_tmp 암호가 비어 있을 때만 `--fastlane-ref` 대신 **`--fastlane-empty`**를 지정합니다. 읽기 실패를 빈 암호로 취급하지 않습니다. 등록 전에 대상 키체인을 짧게 잠갔다가 지정된 원본으로 열어 **실제 암호가 맞는지 검증**합니다.

한 키체인만 필요하면 그 원본만 지정합니다. 일반 재실행은 같은 helper를 재사용합니다. helper 소스·서명을 갱신하는 설치는 캐시 ACL도 다시 연결해야 하므로 **기존 대상 모두의 원본**을 지정해야 합니다.

### 1Password 공유 항목에서 최초 이전

공유받은 항목이 현재 `op` 계정에 없는 경우에는 `--laputa-stdin`으로 **보호된 파이프**를 helper에 연결할 수 있습니다. 자동화는 공유 항목을 메모리에서만 전달해야 하며 암호를 셸 명령·파일에 직접 적거나 출력하면 안 됩니다. 공유 URL을 설정 파일에 저장하지 않습니다.

이 방식의 로그인 자동 해제는 동일하게 동작합니다. 원본 갱신을 `op`로 자동화하려면 나중에 `install --laputa-ref 'op://...'`로 실제 원본 참조를 연결합니다. 연결 전 `refresh`는 참조가 필요하다는 안내와 함께 종료합니다.

## 적용되는 잠금·접근 권한

- `no-timeout`, `lock-on-sleep` 없음
- 서명 키의 신뢰 도구: `/usr/bin/codesign`, `/usr/bin/security`, `/usr/bin/productbuild`, `/usr/bin/productsign`
- 필수 partition: `apple-tool:`, `apple:`, `codesign:`
- **기존 신뢰 앱·`teamid:`·`cdhash:`·partition plist 확장 필드를 보존**하고 누락 항목만 추가
- 이미 정상인 ACL은 다시 쓰지 않음
- 기존 서명 ACL이 모든 앱을 허용하면 더 넓히지 않고, 키체인 접근에서 먼저 제한하라고 안내

파일 키체인의 ACL을 다루는 macOS 공개 API가 필요해 Objective-C helper를 사용합니다. 기본은 보유한 유효한 코드 서명 인증서로 helper를 서명합니다. **Installer 인증서만 있는 Mac도 지원**하며, 이때는 로컬 ad-hoc 서명과 해당 helper의 정확한 코드 식별자로 접근을 제한합니다.

## 확인·갱신·검증·제거

```bash
bash macos/mac-setup.sh --keychains-only status
bash macos/mac-setup.sh --keychains-only refresh
bash macos/mac-setup.sh --keychains-only verify
bash macos/mac-setup.sh --keychains-only uninstall
```

- `status`: 실제 잠금 설정·서명 ACL·helper 전용 캐시·LaunchAgent 등록 확인
- `refresh`: 1Password 원본으로 암호화 캐시 갱신
- `verify`: 캐시를 먼저 읽은 뒤 **실제 잠금 → UI 없는 자동 해제** 확인. 유효한 개발·배포 인증서 각각 2회 `codesign` 서명·엄격 검증. 설치 인증서는 `productsign` 2회·`pkgutil --check-signature` 검증. 보안 입력 창이 나타나면 무암호 성공으로 판정하지 않음
- `uninstall`: 로그인 작업·전용 helper·전용 서비스의 암호화 캐시 제거. 반복 실행 가능

검증 파일은 임시 디렉터리에서 만들고 성공·실패 뒤 정리합니다. 패키지는 설치하지 않습니다. **codesigning identity가 0개여도 Installer 실패로 판정하지 않으며**, basic 정책과 인증서 종류를 별도로 확인합니다. 인증서·개인 키 쌍 자체가 없으면 이유를 보고합니다.

### Fastlane 임시 키체인 재생성

Fastlane이 키체인을 삭제·재생성하고 암호를 새로 정하면 원본·암호화 캐시도 갱신해야 합니다. 캐시의 잘못된 암호로 열지 못하면 입력 창 없이 실패합니다. CI job이 만드는 키체인은 **그 생성 단계에서도** 잠금 해제·서명 ACL을 적용해야 합니다. 이 설정은 현재 사용자 세션의 등록된 키체인을 담당합니다.

## 설치 위치

- helper·설정·상태 로그: `~/Library/Application Support/co-code/signing-keychains/` (디렉터리 `0700`, 설정·로그 `0600`)
- LaunchAgent: `~/Library/LaunchAgents/im.cocode.desktop.signing-keychains.plist`
- 암호화 캐시: **login 키체인**의 `im.cocode.desktop.signing-keychains.v1` service. 기본 키체인이 fastlane_tmp여도 login에만 저장

## 개발 검증

```bash
bash -n macos/mac-setup.sh
/usr/bin/python3 -B macos/signing-keychains/tests.py
```

테스트는 사용자의 암호·인증서를 쓰지 않습니다. 별도 키체인과 메모리에서 생성한 암호로 다른 프로세스의 읽기 거부, 프로세스를 바꾼 자동 해제, 빈 암호, 잠긴 login, 실제 개인 키의 누락 ACL 보완·멱등성·기존 teamid 보존을 검증합니다. 테스트 종료 시 키체인과 검색 목록을 정리합니다.
