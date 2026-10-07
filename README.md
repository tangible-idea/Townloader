# Townloader

인스타그램 게시물·릴스·캐러셀·스토리·하이라이트와 Threads 공개 게시물을 내려받는 Flutter 앱입니다.
인스타그램 정보는 [HikerAPI](https://hikerapi.com/), Threads 정보는 공개 embed 페이지를 통해
조회하고, 파일은 각 서비스의 CDN 에서 직접 스트리밍해 저장합니다.

## 지원 범위

| 입력 | 예시 | 동작 |
| --- | --- | --- |
| 게시물 | `instagram.com/p/<code>/` | 사진 또는 캐러셀 전체 |
| 릴스 · IGTV | `instagram.com/reel/<code>/`, `/reels/`, `/tv/` | 해상도 선택 후 mp4 |
| 스토리 단건 | `instagram.com/stories/<user>/<id>/` | 사진/동영상 |
| 계정 스토리 전체 | `instagram.com/stories/<user>/` | 현재 올라온 스토리 전부 |
| 하이라이트 | `instagram.com/stories/highlights/<id>/` | 하이라이트 항목 전부 |
| 공유 링크 | `instagram.com/share/...`, `instagram.com/s/...` | 서버에서 원본을 찾아 처리 |
| 프로필 | `instagram.com/<user>/`, `@user`, `user` | 프로필 화면에서 목록 탐색 |
| Threads 게시물 | `threads.com/@<user>/post/<code>`, `threads.com/t/<code>` | 공개 사진·동영상·캐러셀 |

공개 계정만 조회할 수 있습니다. 비공개 계정은 HikerAPI 또는 Threads 공개 embed가 접근하지 못합니다.

## 시작하기

### 1. HikerAPI 액세스 키 발급

[hikerapi.com](https://hikerapi.com/) 에서 계정을 만들고 대시보드에서 access key 를 받습니다.
호출 건수만큼 과금되므로, 프로필 목록을 반복해서 새로 고치면 비용이 늘어납니다.

### 2. 실행

```bash
flutter pub get
flutter run -d macos     # 또는 -d <iPhone 기기 ID>
```

### 3. 키를 빌드에 심기

인스타그램 조회는 빌드에 심어 둔 HikerAPI 키만 씁니다. 앱 안에서 키를 넣거나 바꾸는
화면은 없습니다. `.env.json.example` 을 `.env.json` 으로 복사해 키를 채웁니다.

```bash
cp .env.json.example .env.json     # .env.json 은 gitignore 되어 있습니다
```

이후로는 `make` 가 플래그를 붙여 줍니다. 매번 길게 칠 필요가 없습니다.

```bash
make run                 # 연결된 기기로 실행
make run DEVICE=macos    # 기기 지정 (ID 는 make devices)
make ios                 # 연결된 iPhone/iPad 실기기에 Release 빌드·설치·실행
make ios DEVICE=<기기ID>  # 실기기가 여러 대일 때 선택 (ID는 make devices)
make macos               # macOS에서 실행
make ipa                 # 릴리스 빌드
make env-check           # 키가 심기는 상태인지 확인
```

`make ios`는 시뮬레이터를 제외한 iOS 실기기를 자동으로 선택합니다. 설치 후 앱을
실행하고 명령이 종료되며, 기기에서 앱 아이콘을 눌러 다시 실행할 수 있습니다.
연결된 실기기가 없거나 여러 대라면 설치 전에 안내와 함께 중단합니다. iPhone/iPad의
잠금을 해제하고 컴퓨터 신뢰 및 개발자 모드를 켜 두세요. 디버깅과 핫 리로드가 필요하면
`make run DEVICE=<기기ID>`를 사용합니다.

VS Code 를 쓴다면 `.vscode/launch.json` 에 실행 구성이 들어 있어 F5 로 바로 뜹니다.
직접 치고 싶다면 원래 형태도 그대로 유효합니다.

```bash
flutter run --dart-define-from-file=.env.json -d <기기>
```

`.env.json` 없이 빌드하면 Threads 다운로드만 동작하고, 인스타그램 링크는 키가 없다는
안내가 뜹니다.

`.env.json` 에 `POE_API_KEY` 도 넣으면 Threads 댓글 목록에 **댓글 읽어주기** 버튼이 생깁니다.
Poe API 의 `ElevenLabs-v2.5-Turbo` 봇으로 댓글을 한 개씩 음성으로 만들어 차례로 읽고,
읽는 동안 다음 댓글의 음성을 미리 만들어 둡니다. 키가 없으면 버튼이 보이지 않습니다.
Poe 포인트가 글자 수만큼 쓰이니 공개 배포본에는 키를 심지 말고 프록시를 두세요.

> **주의**: 이렇게 심은 키는 비밀이 아닙니다. 컴파일된 스냅샷에 문자열로 남아
> 배포본을 뜯으면 복원할 수 있습니다. HikerAPI 는 호출 건수로 과금하므로,
> 불특정 다수에게 공개 배포하는 빌드에 키를 심으면 크레딧이 소진될 수 있습니다.
> 개인·사내 빌드에만 쓰고, 공개 배포에는 키를 쥔 프록시 서버를 두는 편이 맞습니다.

## 저장 위치

| 플랫폼 | 위치 |
| --- | --- |
| macOS · Windows · Linux | `~/Downloads/Townloader/<계정명>/` |
| iOS · Android | 사진 앱의 `Townloader` 앨범 (설정에서 끄면 앱 문서 폴더) |

파일명은 `계정명_단축코드.확장자` 이고, 캐러셀은 `계정명_단축코드_1.jpg` 처럼 번호가 붙습니다.
같은 이름이 이미 있으면 `-2` 가 덧붙어 덮어쓰지 않습니다.

## 다른 앱에서 공유하기

인스타그램·Threads 의 공유 버튼에서 Townloader 를 고르면 앱이 열리면서 링크를 해석하고,
결과 전체를 바로 다운로드 큐에 넣습니다. 프로필 링크는 프로필 화면으로 엽니다.

- **iOS**: `ios/ShareExtension` 공유 확장이 링크를 꺼내 `townloader://share?url=...` 로
  본 앱을 엽니다. 링크를 URL 에 실어 보내므로 App Group 이 필요 없습니다.
- **Android**: `ACTION_SEND`(`text/plain`) 인텐트 필터로 받습니다.

두 플랫폼 모두 `townloader/share` 메서드 채널로 Dart(`ShareIntake`)에 넘깁니다.

## 구조

```
lib/
  models/       IgUser · IgPost · IgItem · IgAsset — 앱이 쓰는 형태의 미디어 모델
  data/
    ig_url.dart       입력 문자열 → 링크 종류 판정 (네트워크 없음)
    hiker_client.dart api.hikerapi.com HTTP 래퍼 + 오류 메시지 변환
    media_parser.dart 원시 JSON → 모델 (v1/v2/gql·피드/스토리 형태 차이 흡수)
    ig_repository.dart 링크 종류에 맞는 엔드포인트 선택
  services/
    settings_store.dart   키체인 우선, 실패 시 컨테이너 파일로 폴백
    download_service.dart 동시 3개 제한 큐 + 진행률 + 취소/재시도
    file_saver.dart       데스크톱은 디스크, 모바일은 사진 앨범
  state/        ChangeNotifier 컨트롤러 (설정 · 링크 해석 · 프로필)
  ui/           화면과 위젯 (좁은 화면은 하단 탭, 넓은 화면은 사이드 레일)
```

API 키는 `HikerClient` 가 호출할 때마다 `SettingsController` 에서 읽어갑니다.
그래서 설정에서 키를 바꿔도 객체를 다시 만들 필요가 없습니다.

## 테스트

```bash
flutter test                                              # 유닛 42개
flutter test integration_test/platform_smoke_test.dart -d macos   # 플랫폼 6개
```

유닛 테스트는 URL 파싱, HikerAPI 응답 파싱(실제 응답 형태를 줄인 픽스처), 파일명 규칙을
검증합니다. 통합 테스트는 플러그인 채널이 필요한 것 — 설정 저장의 왕복과 다운로드·임시
폴더 접근 — 을 실제 기기에서 확인합니다.

## 알아두기

내려받은 파일의 저작권은 원저작자에게 있습니다. 재배포하거나 상업적으로 쓰기 전에
권리를 확인하세요. 이 앱은 공개된 미디어를 개인적으로 보관하는 용도를 전제로 합니다.
