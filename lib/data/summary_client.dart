import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/threads_thread.dart';
import '../services/usage_meter.dart';

/// 스레드 요약 결과. [summary] 는 본문 요약(5줄 이하, 줄마다 한 문장),
/// [comments] 는 댓글 요점(없으면 빈 목록). [provider]·[model] 은 A/B 테스트로 서버가
/// 정한 것으로, 평가를 보낼 때만 쓴다. 키는 프록시에만 있다.
class ThreadDigest {
  const ThreadDigest({
    required this.summary,
    required this.comments,
    required this.provider,
    required this.model,
  });

  final List<String> summary;
  final List<String> comments;
  final String provider;
  final String model;
}

/// 요약에 대한 평가.
enum SummaryVote { up, down }

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

  /// 서버가 글을 구분하는 값.
  static String threadId(ThreadsThread thread) {
    final root = thread.root;
    return '${root.source.name}-${root.code ?? root.pk}';
  }

  Future<ThreadDigest> summarize(
    ThreadsThread thread, {
    required bool isKo,
  }) async {
    final body = {
      'kind': 'digest',
      'id': threadId(thread),
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

    final response = await _post('/summarize', body);
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
    final provider = data['provider'];
    if (provider is! String) throw SummaryException();
    return ThreadDigest(
      summary: summary,
      comments: comments,
      provider: provider,
      model: data['model'] is String ? data['model'] as String : '',
    );
  }

  /// 요약 평가를 보낸다. [vote] 가 null 이면 [voteId] 로 남긴 평가를 지운다.
  Future<void> sendFeedback(
    ThreadsThread thread, {
    required ThreadDigest digest,
    required bool isKo,
    required String voteId,
    required SummaryVote? vote,
  }) async {
    final response = await _post('/summary-feedback', {
      'provider': digest.provider,
      'model': digest.model,
      'id': threadId(thread),
      'lang': isKo ? 'ko' : 'en',
      'voteId': voteId,
      'vote': vote?.name ?? 'none',
    });
    if (response.statusCode != 200) throw SummaryException();
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    try {
      return await _http
          .post(
            Uri.parse('$_baseUrl$path'),
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
  }

  void close() => _http.close();
}
