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
  static const String hikerApiKey = String.fromEnvironment('HIKER_API_KEY');

  static bool get hasBundledHikerKey => hikerApiKey.isNotEmpty;

  /// 댓글을 읽어 줄 때 쓰는 Poe API 키(ElevenLabs 음성). 안 넘기면 읽기 버튼이 숨는다.
  /// HikerAPI 키와 마찬가지로 배포본에서 꺼낼 수 있으니 공개 배포에는 프록시를 둔다.
  static const String poeApiKey = String.fromEnvironment('POE_API_KEY');

  static bool get hasPoeKey => poeApiKey.isNotEmpty;

  /// 스레드 요약 프록시(Cloudflare Worker) 주소. 안 넘기면 요약 카드가 숨는다.
  /// Claude·Poe 키는 프록시에만 있고 앱에는 들어가지 않는다.
  static const String summaryProxyUrl = String.fromEnvironment(
    'SUMMARY_PROXY_URL',
  );

  /// 프록시가 확인하는 앱 토큰. 비밀은 아니며, 아무 요청이나 받지 않게 하는 관문이다.
  static const String summaryAppToken = String.fromEnvironment(
    'SUMMARY_APP_TOKEN',
  );

  static bool get hasSummaryProxy => summaryProxyUrl.isNotEmpty;
}
