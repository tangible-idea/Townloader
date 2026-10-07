import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Poe API 로 ElevenLabs Turbo 음성을 만든다.
///
/// Poe 는 OpenAI 호환 `chat/completions` 로 봇을 부른다. 음성 봇은 글로 된 답 대신
/// 만들어진 오디오 파일의 주소를 메시지 안에 실어 돌려주므로, 그 주소를 꺼내 쓴다.
class PoeTtsClient {
  PoeTtsClient({required this.apiKey, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _http;

  static final Uri endpoint = Uri.parse(
    'https://api.poe.com/v1/chat/completions',
  );

  /// Poe 의 봇 이름. Turbo v2.5 는 빠르고 한국어도 읽는다.
  static const String model = 'ElevenLabs-v2.5-Turbo';

  static const Duration timeout = Duration(seconds: 60);

  /// [text] 를 읽은 오디오 파일 주소를 돌려준다.
  Future<Uri> synthesize(String text) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: {
              'authorization': 'Bearer $apiKey',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': text},
              ],
              'stream': false,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw PoeTtsException('음성을 만드는 데 시간이 너무 오래 걸립니다.');
    }

    if (response.statusCode != 200) {
      throw PoeTtsException(switch (response.statusCode) {
        401 || 403 => 'Poe API 키가 올바르지 않습니다.',
        402 => 'Poe 포인트가 부족합니다.',
        429 => '요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.',
        _ => '음성을 만들지 못했습니다 (HTTP ${response.statusCode}).',
      }, statusCode: response.statusCode);
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final url = audioUrlFrom(body);
    if (url == null) {
      throw PoeTtsException('응답에서 오디오를 찾지 못했습니다.');
    }
    return url;
  }

  static final _url = RegExp(r'''https?://[^\s<>()\[\]"']+''');

  /// 응답에서 오디오 주소를 찾는다.
  ///
  /// 보통 `choices[0].message.content` 에 주소가 그대로 오거나 마크다운 링크로 온다.
  /// 형태가 바뀌어도 버티도록, 거기서 못 찾으면 응답 전체에서 오디오 파일로 보이는
  /// 주소를 찾는다.
  static Uri? audioUrlFrom(String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }

    final content = _content(json);
    if (content != null) {
      final match = _url.firstMatch(content);
      if (match != null) return Uri.tryParse(match.group(0)!);
    }

    for (final match in _url.allMatches(body)) {
      final candidate = match.group(0)!;
      if (RegExp(r'\.(mp3|wav|m4a|aac|ogg)(\?|$)').hasMatch(candidate) ||
          candidate.contains('poecdn')) {
        return Uri.tryParse(candidate);
      }
    }
    return null;
  }

  /// `content` 는 문자열이거나 `{type: text, text: ...}` 조각의 목록이다.
  static String? _content(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final message = (choices.first as Map<String, dynamic>?)?['message'];
    if (message is! Map<String, dynamic>) return null;
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return [
        for (final part in content)
          if (part is Map<String, dynamic>)
            (part['text'] ?? part['url'] ?? part['audio_url'] ?? '').toString(),
      ].join('\n');
    }
    return null;
  }

  void close() => _http.close();
}

class PoeTtsException implements Exception {
  PoeTtsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
