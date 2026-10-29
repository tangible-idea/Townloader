import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/saved_link.dart';

class PlacesException implements Exception {
  PlacesException(this.message, {this.rateLimited = false});

  final String message;

  /// 하루 분석 횟수를 다 썼으면 true.
  final bool rateLimited;

  @override
  String toString() => message;
}

/// 프록시(Cloudflare Worker)의 `/places` 로 글 하나의 장소를 찾는다.
/// 요청 형식은 `proxy/src/places.ts` 의 `PlacesRequest` 와 같다.
class PlacesClient {
  PlacesClient({String? baseUrl, String? appToken, http.Client? httpClient})
    : _baseUrl = baseUrl ?? AppConfig.proxyUrl,
      _appToken = appToken ?? AppConfig.proxyAppToken,
      _http = httpClient ?? http.Client();

  final String _baseUrl;
  final String _appToken;
  final http.Client _http;

  static const Duration timeout = Duration(seconds: 90);

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<List<SavedPlace>> findPlaces(Map<String, Object?> request) async {
    if (!isConfigured) {
      throw PlacesException('장소를 찾는 서버가 이 빌드에 설정되어 있지 않습니다.');
    }
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_baseUrl/places'),
            headers: {
              'content-type': 'application/json',
              'x-app-token': _appToken,
            },
            body: jsonEncode(request),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw PlacesException('장소를 찾는 데 시간이 너무 오래 걸립니다.');
    } on Exception {
      throw PlacesException('장소를 찾는 서버에 연결하지 못했습니다.');
    }

    if (response.statusCode == 429) {
      throw PlacesException('오늘 분석할 수 있는 횟수를 다 썼습니다.', rateLimited: true);
    }
    if (response.statusCode != 200) {
      throw PlacesException('장소를 찾지 못했습니다 (HTTP ${response.statusCode}).');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final places = data is Map ? data['places'] : null;
    if (places is! List) throw PlacesException('장소 응답을 읽지 못했습니다.');
    return [
      for (final place in places)
        if (place is Map<String, dynamic>) SavedPlace.fromJson(place),
    ];
  }

  /// 저장한 글의 짧은 대표 제목. 못 지으면 null 이고, 오류도 null 로 넘긴다(제목은 없어도 된다).
  Future<String?> title({
    required String code,
    required bool isKo,
    String? caption,
    List<String> places = const [],
    List<String> lines = const [],
  }) async {
    if (!isConfigured) return null;
    try {
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/title'),
            headers: {
              'content-type': 'application/json',
              'x-app-token': _appToken,
            },
            body: jsonEncode({
              'code': code,
              'lang': isKo ? 'ko' : 'en',
              'caption': caption ?? '',
              'places': places,
              'lines': lines,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final title = data is Map ? data['title'] : null;
      return title is String && title.trim().isNotEmpty ? title.trim() : null;
    } on Exception {
      return null;
    }
  }

  void close() => _http.close();
}
