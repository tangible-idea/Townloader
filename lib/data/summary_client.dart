import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/threads_thread.dart';
import '../services/usage_meter.dart';

/// 요약을 만드는 AI 공급자. 키는 프록시에만 있다.
enum SummaryProvider {
  claude('Anthropic (Claude)'),
  poe('Poe');

  const SummaryProvider(this.label);

  /// 동의 안내에 보여 줄 서비스 이름.
  final String label;
}

/// 무엇을 요약할지.
enum SummaryKind {
  /// 작성자의 글을 중심으로 스레드 전체를.
  thread,

  /// 댓글만. 작성자의 글은 댓글이 무엇에 대한 것인지 알려 주는 데만 쓴다.
  comments,
}

class SummaryException implements Exception {
  SummaryException({this.rateLimited = false});

  /// 하루 요약 횟수를 다 썼으면 true.
  final bool rateLimited;
}

/// 요약 프록시(Cloudflare Worker)에 스레드 글과 댓글을 보내 요약을 받는다.
class SummaryClient {
  SummaryClient({String? baseUrl, String? appToken, http.Client? httpClient})
    : _baseUrl = baseUrl ?? AppConfig.proxyUrl,
      _appToken = appToken ?? AppConfig.proxyAppToken,
      _http = httpClient ?? UsageClient();

  final String _baseUrl;
  final String _appToken;
  final http.Client _http;

  static const Duration timeout = Duration(seconds: 60);

  Future<String> summarize(
    ThreadsThread thread, {
    required SummaryProvider provider,
    required bool isKo,
    SummaryKind kind = SummaryKind.thread,
  }) async {
    final root = thread.root;
    final body = {
      'provider': provider.name,
      'kind': kind.name,
      'id': '${root.source.name}-${root.code ?? root.pk}',
      'lang': isKo ? 'ko' : 'en',
      'posts': [
        for (final node in thread.nodes)
          if ((node.post.caption ?? '').trim().isNotEmpty)
            {
              'author': node.post.authorName,
              'text': node.post.caption!.trim(),
              'byAuthor': node.isByAuthor,
            },
      ],
    };

    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_baseUrl/summarize'),
            headers: {
              'content-type': 'application/json',
              'x-app-token': _appToken,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception {
      throw SummaryException();
    }

    if (response.statusCode == 429) throw SummaryException(rateLimited: true);
    if (response.statusCode != 200) throw SummaryException();
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final summary = data is Map ? data['summary'] : null;
    if (summary is! String || summary.trim().isEmpty) throw SummaryException();
    return summary.trim();
  }

  void close() => _http.close();
}
