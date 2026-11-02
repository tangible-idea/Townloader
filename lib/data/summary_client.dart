import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/threads_thread.dart';
import '../services/usage_meter.dart';

/// 요약을 만드는 AI. 동의 안내에 보여 줄 이름이고, 키는 프록시에만 있다.
const summaryProviderLabel = 'Anthropic (Claude)';

/// 스레드 요약 결과. [summary] 는 본문 요약(5줄 이하, 줄마다 한 문장),
/// [comments] 는 댓글 요점(없으면 빈 목록).
class ThreadDigest {
  const ThreadDigest({required this.summary, required this.comments});

  final List<String> summary;
  final List<String> comments;
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

  Future<ThreadDigest> summarize(
    ThreadsThread thread, {
    required bool isKo,
  }) async {
    final root = thread.root;
    final body = {
      'kind': 'digest',
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
    if (data is! Map) throw SummaryException();
    final summary = [
      for (final line in '${data['summary'] ?? ''}'.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ].take(5).toList();
    if (summary.isEmpty) throw SummaryException();
    final comments = [
      for (final point
          in data['comments'] is List ? data['comments'] as List : const [])
        if ('$point'.trim().isNotEmpty) '$point'.trim(),
    ];
    return ThreadDigest(summary: summary, comments: comments);
  }

  void close() => _http.close();
}
