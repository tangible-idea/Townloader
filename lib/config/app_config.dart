/// 빌드 시점에 심어 두는 설정값.
///
/// 값은 `--dart-define-from-file=.env.json` 으로 넘긴다.
///
///     flutter run  --dart-define-from-file=.env.json -d <기기>
///     flutter build ipa --dart-define-from-file=.env.json
///
/// 주의: 여기 심은 값은 비밀이 아니다. 컴파일된 스냅샷에 문자열로 남으므로
/// 배포본을 뜯으면 복원할 수 있다. HikerAPI 는 호출 건수로 과금하니, 공개
/// 배포본에 키를 심으면 크레딧이 소진될 수 있다. 사내·개인용 빌드에만 쓰고,
/// 공개 배포에는 키를 쥔 프록시 서버를 두는 편이 맞다.
class AppConfig {
  const AppConfig._();

  /// 빌드에 심어 둔 HikerAPI 액세스 키. 안 넘기면 빈 문자열이다.
  /// 프록시를 쓰는 빌드에서는 넣지 않는다. 개발용으로 직접 부를 때만 쓴다.
  static const String hikerApiKey = String.fromEnvironment('HIKER_API_KEY');

  static bool get hasBundledHikerKey => hikerApiKey.isNotEmpty;

  /// 댓글을 읽어 줄 때 쓰는 Poe API 키(ElevenLabs 음성). 안 넘기면 읽기 버튼이 숨는다.
  /// HikerAPI 키와 마찬가지로 배포본에서 꺼낼 수 있으니 공개 배포에는 프록시를 둔다.
  static const String poeApiKey = String.fromEnvironment('POE_API_KEY');

  static bool get hasPoeKey => poeApiKey.isNotEmpty;

  /// 키를 쥔 프록시(Cloudflare Worker, `proxy/`) 주소. HikerAPI 조회와 스레드 요약이
  /// 이곳을 거치고, HikerAPI·Claude·Poe 키는 프록시에만 있다.
  /// 안 넘기면 HikerAPI 는 [hikerApiKey] 로 직접 부르고 요약 카드는 숨는다.
  static const String proxyUrl = String.fromEnvironment('PROXY_URL');

  /// 프록시가 확인하는 앱 토큰. 비밀은 아니며, 아무 요청이나 받지 않게 하는 관문이다.
  static const String proxyAppToken = String.fromEnvironment('PROXY_APP_TOKEN');

  static bool get hasProxy => proxyUrl.isNotEmpty;

  /// Mapbox 공개 토큰(`pk.`). 저장한 글을 지구본에 띄우는 데 쓴다. 공개 토큰은 앱에
  /// 들어가도 되는 값이지만, Mapbox 계정에서 사용 범위를 제한해 두는 편이 좋다.
  static const String mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

  static bool get hasMapbox => mapboxToken.isNotEmpty;
}
