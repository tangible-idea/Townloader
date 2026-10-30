import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 바깥 유료 서비스 하나와 그 1회 호출의 값(토큰).
///
/// 토큰은 비용을 비교하려고 정한 단위다. 가장 싼 Jev 1회를 1토큰(약 $0.0001)으로 두고,
/// 나머지는 1회 호출의 대략적인 비용을 그 배수로 적었다. 실제 청구액이 아니라 추정치라서
/// 가격이 바뀌면 [weight] 만 고치면 된다.
class UsageService {
  const UsageService(this.key, this.weight, this.ko, this.en);

  /// 서버의 `x-usage` 헤더와 같은 이름(proxy/src/usage.ts).
  final String key;
  final int weight;
  final String ko;
  final String en;
}

const usageServices = [
  // 입력 1백만 토큰에 $0.042. 장소 줄 분류·매칭 판정 1회가 수천 토큰이라 약 $0.0001.
  UsageService('jev', 1, 'Jev 판단', 'Jev judgment'),
  // 무료 할당량 안에서 쓰지만, 한도가 있는 자원이라 Jev 와 같은 값으로 센다.
  UsageService('kakao', 1, '카카오맵 검색', 'Kakao Map search'),
  // 지오코딩 1천 건에 $0.75 → 1회 약 $0.00075.
  UsageService('mapbox', 8, 'Mapbox API', 'Mapbox API'),
  // 지도 화면을 한 번 여는 것. 지도 타일·스타일 로드.
  UsageService('mapbox_map', 10, 'Mapbox 지도 열기', 'Mapbox map load'),
  // 장소 글 제목 짓기(Claude Haiku). 짧은 입력·출력이라 약 $0.0006.
  UsageService('claude_haiku', 6, 'Claude Haiku (제목)', 'Claude Haiku (titles)'),
  // 스레드 요약(Claude Opus). 입력 수천·출력 수백 토큰이라 약 $0.035.
  UsageService('claude', 350, 'Claude Opus (요약)', 'Claude Opus (summaries)'),
  // Poe 의 Claude Sonnet 봇(본문 장소 읽기·요약 대체). 1회 약 $0.015.
  UsageService('poe', 150, 'Poe 챗봇', 'Poe chat bot'),
  // Poe 의 ElevenLabs 음성(댓글 읽어 주기). 1회 약 $0.05.
  UsageService('poe_tts', 500, 'Poe 음성(ElevenLabs)', 'Poe voice (ElevenLabs)'),
];

/// 이 기기에서 바깥 서비스를 부른 횟수를 모아 토큰으로 계산한다.
///
/// 서버를 거친 호출은 응답의 `x-usage` 헤더로, 앱이 직접 부른 호출은 주소로 센다.
/// 횟수는 앱 지원 폴더의 파일에 남는다.
class UsageMeter extends ChangeNotifier {
  UsageMeter._() {
    unawaited(_load());
  }

  static final instance = UsageMeter._();

  final Map<String, int> _counts = {};
  DateTime? _since;
  Timer? _saveTimer;

  Map<String, int> get counts => Map.unmodifiable(_counts);

  /// 세기 시작한 때(처음 쓴 때, 또는 마지막으로 초기화한 때).
  DateTime? get since => _since;

  int countOf(UsageService service) => _counts[service.key] ?? 0;
  int tokensOf(UsageService service) => countOf(service) * service.weight;
  int get totalTokens =>
      usageServices.fold(0, (sum, service) => sum + tokensOf(service));

  void add(String key, [int count = 1]) {
    if (count <= 0) return;
    _counts[key] = (_counts[key] ?? 0) + count;
    _since ??= DateTime.now();
    notifyListeners();
    _scheduleSave();
  }

  /// 서버 응답의 `x-usage` 헤더({"jev":2,"kakao":7})를 더한다.
  void addHeader(String? header) {
    if (header == null || header.isEmpty) return;
    try {
      final decoded = jsonDecode(header);
      if (decoded is! Map) return;
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (key is String && value is num) add(key, value.toInt());
      }
    } on FormatException {
      return;
    }
  }

  void reset() {
    _counts.clear();
    _since = DateTime.now();
    notifyListeners();
    _scheduleSave();
  }

  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/usage.json');

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      final counts = data['counts'];
      if (counts is Map) {
        for (final MapEntry(:key, :value) in counts.entries) {
          // 읽는 사이에 센 것과 합친다.
          if (key is String && value is num) {
            _counts[key] = (_counts[key] ?? 0) + value.toInt();
          }
        }
      }
      final since = DateTime.tryParse('${data['since'] ?? ''}');
      if (since != null) _since = since;
      notifyListeners();
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      try {
        await (await _file()).writeAsString(
          jsonEncode({'counts': _counts, 'since': _since?.toIso8601String()}),
        );
      } catch (_) {}
    });
  }
}

/// 응답을 보고 [UsageMeter] 에 센다. 서버 응답은 `x-usage` 헤더로, 카카오·Mapbox·Poe 를
/// 직접 부른 것은 주소로 가린다.
class UsageClient extends http.BaseClient {
  UsageClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final meter = UsageMeter.instance;
    final header = response.headers['x-usage'];
    if (header != null) {
      meter.addHeader(header);
    } else {
      final key = _directKey(request.url.host);
      if (key != null) meter.add(key);
    }
    return response;
  }

  static String? _directKey(String host) {
    if (host == 'api.poe.com') return 'poe_tts';
    if (host.endsWith('.kakao.com')) return 'kakao';
    if (host.endsWith('.mapbox.com')) return 'mapbox';
    return null;
  }

  @override
  void close() => _inner.close();
}
