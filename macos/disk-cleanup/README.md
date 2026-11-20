# 🧹 디스크 자동 정리 (macOS)

> 맥 디스크를 조용히 채우는 **'쓰고 나서 아무도 치우지 않는 파일'** 을 정해진 주기로 치우는 예약 작업(launchd) 4개입니다. `mac-setup.sh` 전체 설치의 9.5단계에서 등록되고, 이미 세팅한 맥은 `./mac-setup.sh --cleanup-only` 로 이 단계만 실행할 수 있습니다.

<br>

## 무엇을 언제 지우나요

| 작업 (launchd 이름) | 주기 | 대상 | 이럴 때만 지웁니다 |
|---|---|---|---|
| `im.cocode.dart-tmp-cleanup` | 15분마다 | 임시 폴더의 `dart_test.kernel.*` · `flutter_tools.*` — Flutter·Dart 테스트를 중간에 끊거나 CI 잡이 취소되면 남는 폴더 (개당 수 GB~수십 GB) | 쓰는 프로세스가 없고, 그 안에서 바뀐 파일이 `dart_test.kernel.*` 는 **70분**, `flutter_tools.*` 는 **6시간** 동안 하나도 없을 때. `dart_test.kernel.*` 는 그 폴더를 만든 러너·워크트리에서 `dart test` 가 돌고 있어도 남깁니다 |
| `im.cocode.runner-cache-cleanup` | 하루마다 | self-hosted 러너가 러너마다 따로 둔 캐시 사본 — `~/.gradle-*` · `~/.pub-cache-*` · `~/actions/_cache*/pub-*` · `~/Library/Developer/Xcode/DerivedData-<러너>` · `Archives-<러너>.xcarchive` — 와 러너 작업 폴더 `~/actions/<러너>/_work/<저장소>` | 쓰는 프로세스가 없고, 그 안에서 바뀐 파일이 캐시 사본은 **72시간**, 작업 폴더는 **14일** 동안 하나도 없을 때. 이름이 `*-shared` 인 공용 캐시와 `_tool` · `_temp` 처럼 `_` 로 시작하는 러너 내부 폴더는 지우지 않습니다. **러너가 없는 맥은 할 일이 없습니다** |
| `im.cocode.docker-disk-cleanup` | 하루마다 | Colima(맥에서 Docker 를 돌리는 VM)의 빌드 캐시 · 주인 없는 익명 볼륨, 그리고 VM 안에서 지운 공간을 맥으로 돌려주는 `fstrim` | 빌드 캐시는 **72시간** 동안 쓰지 않은 것. 볼륨은 어떤 컨테이너(멈춘 것 포함)에도 붙어 있지 않고, 이름이 자동으로 붙은 64자리 해시이며, 만든 지 **72시간**이 넘은 것. **Colima 가 꺼져 있으면 쉽니다** |
| `im.cocode.runner-cache-dedupe` | 하루마다 | self-hosted 러너가 러너마다 따로 받은 **같은 파일** — Flutter SDK(`_work/_tool/flutter` · `_tool/flutter-<러너>`) · pub 캐시 · Gradle 홈 · `_work/_tool` 의 dart·node·JDK 등 — 을 **지우지 않고** 복제본(APFS clone)으로 바꿔 디스크 블록을 한 벌로 합치기 | 파일이 **쉬고 있는 러너**의 것이고, 공용 캐시(`*-shared` 등)가 아니고, 최근 **10분** 안에 바뀌지 않았고, 다른 러너의 파일과 내용(SHA-256)이 완전히 같을 때만 바꿉니다. 잡을 돌리는 러너와 공용 캐시는 읽기만 합니다. **러너가 둘 미만인 맥은 할 일이 없습니다** |

러너 이름은 `~/actions/<이름>/.runner` 파일이 있는 폴더로 판별합니다. 개인 Xcode 캐시(`~/Library/Developer/Xcode/DerivedData`)처럼 러너 이름이 붙지 않은 것은 대상이 아닙니다.

<br>

## 지우지 않는 것

- **실행 중이거나 최근에 바뀐 것** — 위 조건을 모두 만족해야 지웁니다. 하나라도 걸리면 남깁니다.
- **Docker 이미지 · 컨테이너 · 네트워크 · 이름 붙은 볼륨** — 직접 빌드해 다시 만드는 데 오래 걸리는 이미지나, 일부러 남겨 둔 데이터일 수 있습니다. Colima 를 켜거나 끄지도 않습니다.
- **러너의 Flutter SDK** (`_work/_tool/flutter`) — unibook 레포의 `prune-stale-flutter-sdk.yml` 이 러너를 함께 쓰는 모든 저장소의 버전을 모아 무엇을 남길지 정합니다. 두 곳이 같은 폴더를 지우면 그 보존 목록이 무의미해집니다. 사본 합치기(`runner-cache-dedupe`)는 이 폴더를 지우지 않고 파일을 같은 내용의 복제본으로 바꾸기만 하므로 그 보존 목록과 부딪히지 않습니다.

<br>

## 확인하기

```bash
launchctl list | grep im.cocode                      # 네 작업이 보이면 등록된 것
tail ~/Library/Logs/dart-tmp-cleanup.log ~/Library/Logs/runner-cache-cleanup.log ~/Library/Logs/docker-disk-cleanup.log ~/Library/Logs/runner-cache-dedupe.log
DRY_RUN=1 sh ~/.local/bin/cleanup-runner-cache.sh    # 지우지 않고 대상만 보기
DRY_RUN=1 sh ~/.local/bin/cleanup-docker-disk.sh     # (Colima 가 켜져 있을 때)
DRY_RUN=1 sh ~/.local/bin/dedupe-runner-cache.sh     # 바꾸지 않고 합칠 수만 보기 (러너가 둘 이상일 때)
```

기록은 무언가를 지웠을 때 한 줄씩 남습니다(Docker 작업은 하루 한 줄, 사본 합치기는 무언가 바꿨거나 문제가 있을 때만). 400줄이 넘으면 뒤쪽 200줄만 남깁니다. `mac-setup.sh` 의 설치 검증에도 `디스크 자동 정리: ✓ 4종 등록됨` 한 줄이 나옵니다.

<br>

## 끄기 · 다시 켜기

```bash
for job in dart-tmp-cleanup runner-cache-cleanup docker-disk-cleanup runner-cache-dedupe; do
  launchctl bootout "gui/$(id -u)/im.cocode.$job"
  rm -f ~/Library/LaunchAgents/im.cocode.$job.plist
done
```

다시 켜려면 `./mac-setup.sh --cleanup-only`. 이미 등록된 맥에서 다시 실행하면 내용이 바뀐 작업만 내렸다가 다시 올립니다.

<br>

## 왜 이렇게 하나요

**두 가지를 다 봅니다.** 프로세스·열린 파일 확인(`ps` · `lsof`)은 조회한 순간의 스냅샷이라, 조회와 삭제 사이에 시작된 실행을 놓칠 수 있습니다. "그 안에서 N시간 동안 바뀐 파일이 없다"는 조건이 그 틈을 막습니다. 반대로 시간만 보면 오래 도는 작업을 지웁니다. 실제로 23GB 짜리 `dart_test.kernel.*` 하나가 실행 중이었던 적이 있습니다.

**맨 위 폴더가 아니라 안의 파일을 봅니다.** 폴더의 수정 시각은 바로 아래 항목이 생기거나 지워질 때만 바뀝니다. 매일 쓰는 pub 캐시도 맨 위 폴더만 보면 '75시간 전'으로 보였고(2026-10-19 실측 — 안쪽은 72시간 안에 바뀜), 그 기준으로 지우면 다음 CI 가 같은 캐시를 다시 받습니다.

**작업 폴더만 14일입니다.** unibook 의 `prune-stale-flutter-sdk.yml` 은 러너에 남은 작업 폴더의 `.fvmrc` 로 남길 Flutter SDK 를 정합니다. 작업 폴더를 지우면 그 저장소의 SDK 도 다음 날 지워질 수 있어, 다음 CI 가 클론과 SDK 다운로드(5~25분)를 둘 다 처음부터 합니다. 며칠에 한 번 도는 저장소가 매번 그 값을 치르지 않도록, 이 맥에서 손을 뗀 저장소만 지웁니다.

**날짜 문자열을 만들지 않습니다.** `find -newermt "2026-10-19T08:04:57"` 처럼 날짜와 시각 사이에 `T` 를 넣으면 macOS `find` 가 다른 시각으로 읽습니다. 실측(2026-10-19): 70분 기준은 5분 전에 바뀐 폴더도 '오래됨'으로 판정했고, 6시간 기준은 약 4시간으로 줄어 있었습니다. 그래서 `find -mmin` 으로 분 단위를 직접 셉니다.

**디스크가 꽉 차도 동작합니다.** 사용 중 목록을 임시 파일에 적으면, 디스크가 가득 찬 순간 그 파일을 못 만들어 정리가 통째로 멈춥니다(기록: `mkstemp failed ... No space left on device`). 정리가 가장 필요한 순간이라 목록을 파일이 아니라 메모리(변수)에 담습니다.

**fstrim 까지 합니다.** Colima 의 데이터 디스크는 한 번 커지면 VM 안에서 지워도 맥 쪽 파일이 줄지 않습니다. `fstrim` 이 VM 안에서 지운 공간을 맥에 돌려줍니다 — 이 단계가 없으면 Docker 를 아무리 비워도 맥 여유는 늘지 않습니다.

**러너 사본은 지우지 않고 합칩니다.** 러너마다 캐시를 따로 두는 것은 서로 덮어쓰는 사고를 막으려는 옳은 선택이지만, 러너가 8개면 같은 Flutter SDK 가 8벌 쌓입니다(2026-11-13 실측: 사본의 논리 크기 합 약 190GB 가 한 벌 크기로 줄었습니다). 지우면 다음 CI 가 SDK 를 다시 받아야 하고(5~25분, 느린 날은 시간 제한 초과) 그동안 러너가 막힙니다. APFS 의 복제(clonefile)는 파일을 만들 때 디스크 블록을 새로 쓰지 않고 원본과 나눠 쓰다가, 한쪽을 고칠 때만 바뀐 부분을 따로 둡니다. 그래서 내용이 같은 파일만 복제본으로 바꾸면 각 러너는 완전한 사본을 그대로 가진 채 디스크 사용량만 한 벌로 줄어듭니다.

**이미 합친 것은 다시 읽지 않습니다.** 두 파일의 물리 배치(`F_LOG2PHYS_EXT`)가 같으면 같은 블록을 나눠 쓰는 복제본이라 내용을 읽을 필요가 없습니다. 그래서 첫 회차 뒤에는 새로 생긴 파일만 읽고, 사본이 수백 GB 쌓인 맥도 한 번에 최대 2시간까지만 일한 뒤 다음 회차에 이어서 합칩니다.

**쉬는 러너의 파일만 바꿉니다.** 복제본으로 바꾸는 일은 이름 바꾸기(rename) 한 번이라 읽는 쪽은 옛 파일이나 새 파일 중 하나를 온전히 봅니다. 하지만 쓰는 중인 파일을 바꾸면 그 쓰기가 사라진 옛 파일로 갑니다. 그래서 잡을 돌리는 러너(`Runner.Worker` 가 있는 러너)와 여러 러너가 함께 쓰는 공용 캐시는 읽기만 하고, 락·pid·로그·DB·`_temp` 처럼 쓰는 중에 바뀌는 이름과 Gradle 의 내부 DB 는 대상에서 뺍니다.

**새로 생기는 사본까지 막지는 못합니다.** 러너를 새로 등록하거나 SDK 를 새로 받으면 그 사본은 다시 따로 저장됩니다. 하루마다 도는 이 작업이 그것을 합치고, 새 러너는 co-package 의 `register-runner.sh` 가 같은 맥의 다른 러너 도구 폴더를 복제해서 시작하게 하면 처음부터 거의 디스크를 쓰지 않습니다([co_arc 안내](https://github.com/coco-de/co-package/tree/main/packages/co_arc)).

**러너 맥에서는 unibook 워크플로와 나눠 맡습니다.** unibook 의 `reclaim-docker-disk.yml` 이 매일 러너 맥의 이미지·빌드 캐시 정리와 `fstrim` 을 합니다. 이 작업은 그와 겹쳐 돌아도 무해하고(이미 지운 것은 다시 지울 게 없습니다), 그 워크플로가 일부러 손대지 않는 볼륨 쪽을 위 조건(주인 없음 · 익명 · 72시간)으로 맡습니다. 그 워크플로가 금지하는 `docker system prune --volumes` 는 이 조건 없이 지우므로 여기서도 쓰지 않습니다.

<br>

## 그래도 디스크가 부족하면

자동 정리는 **반복해서 쌓이는 것**만 다룹니다. 한 번에 크게 차는 것은 직접 확인해 주세요 (2026-10-19 실측으로 컸던 것):

| 확인할 곳 | 메모 |
|---|---|
| `~/.local/share/opencode/opencode.db` | OpenCode 대화 기록 DB. 대화를 지워도 파일이 줄지 않아 45GB 까지 커진 적이 있습니다(그중 92%가 빈 공간). OpenCode 를 모두 끈 뒤 `sqlite3 ~/.local/share/opencode/opencode.db 'VACUUM'` 으로 줄이거나, 기록이 필요 없다면 `opencode.db*` 를 지워도 됩니다 — 로그인 정보는 같은 폴더의 `auth.json` 에 따로 있습니다 |
| 프로젝트의 `build/` · `.dart_tool/` | Flutter 빌드 결과물입니다. 오래 안 연 프로젝트는 `flutter clean` 으로 지워도 다음 빌드 때 다시 만들어집니다 |
| `~/Library/Developer/Xcode/iOS DeviceSupport` | 연결했던 아이폰·아이패드 버전마다 수 GB. 더 이상 쓰지 않는 버전은 지워도 다음 연결 때 다시 받습니다 |
| `docker image ls` | 쓰지 않는 이미지는 직접 고른 뒤 `docker image rm <이름>` |

디스크 사용량을 볼 때는 `du -sh ~/*` 로는 부족합니다 — 숨김 폴더(`~/.gradle*` 등)와 임시 폴더(`$TMPDIR`)가 빠집니다. `du -x -k -d 1 "$HOME" | sort -rn | head` 와 `du -x -k -d 1 "$(getconf DARWIN_USER_TEMP_DIR)" | sort -rn | head` 를 함께 보세요.

<br>

## 배경

self-hosted 러너 여러 개가 함께 도는 팀 맥(994GB)의 여유가 **6.1GB(2026-08-24)**, **1.5GB(2026-10-19)** 까지 떨어졌습니다. 두 번 모두 결함 하나가 아니라, 각자 옳은 이유로 만든 사본(러너별 캐시 격리, 한 번 받으면 오래 두는 SDK, 테스트 임시 폴더)에 **언제 지울지 정한 규칙이 없어서**였습니다.

2026-11-13 에는 여유가 **2.5GB** 까지 떨어졌고, 러너를 멈춘 채 사본을 복제로 합쳐 약 170GB 를 아무것도 지우지 않고 되찾았습니다. 그 방법을 정기 작업(`runner-cache-dedupe`)으로 만든 것입니다.

앞의 두 작업(`dart-tmp-cleanup` · `runner-cache-cleanup`)은 unibook 레포의 `scripts/` 에서 먼저 만들어 러너 맥에 등록했던 것을, 팀 맥 전체에 같은 방식으로 깔리도록 이곳으로 가져왔습니다. 같은 이름으로 등록하므로 이미 등록된 맥에서는 새 판이 그 자리를 갈아끼웁니다.

<br>

## 변경 검증

```bash
python3 -m unittest discover -s tests -p 'test_disk_cleanup.py' -v
```

임시 HOME 에 폴더를 만들고 수정 시각을 바꿔 가며 "남길 것은 남기고 지울 것만 지우는지"를 봅니다. 사본 합치기는 가짜 러너를 만들어 실제로 복제한 뒤 물리 배치를 비교해 "블록을 정말 나눠 쓰는지", 모드·mtime 이 그대로인지, 잡을 돌리는 러너·공용 캐시·락 파일이 그대로인지, 두 번째 회차가 아무것도 다시 읽지 않는지를 봅니다(복제는 macOS 에만 있어 그 검사는 macOS 에서만 돕니다). Docker 작업은 가짜 `docker` · `colima` 명령으로 어떤 명령을 부르는지만 확인합니다 — 실제 Docker 는 건드리지 않습니다. PR 에서는 macOS 와 Ubuntu 에서 함께 돕니다.
