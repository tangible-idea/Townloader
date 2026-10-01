import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/ig_asset.dart';
import '../models/ig_post.dart';
import '../models/ig_user.dart';
import '../models/media_source.dart';
import '../models/threads_thread.dart';
import 'hiker_client.dart';
import 'ig_url.dart';
import 'media_parser.dart';

/// Threads 의 공개 embed 페이지에서 게시물 미디어를 가져온다.
///
/// Threads 공식 API는 다른 사용자의 임의 게시물을 읽는 용도가 아니므로, 로그인 없이
/// 공개되는 embed HTML만 사용한다. 페이지 구조가 달라질 수 있어 파싱은 이 클래스에
/// 격리한다.
class ThreadsClient {
  ThreadsClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const Duration timeout = Duration(seconds: 30);

  Future<IgPost> fetchPost(IgLink link) async {
    final (uri: targetUri, code: targetCode, username: targetUsername) =
        await _resolveTarget(link);

    final embedUri = Uri(
      scheme: targetUri.scheme,
      host: targetUri.host,
      port: targetUri.hasPort ? targetUri.port : null,
      path: '${targetUri.path.replaceFirst(RegExp(r'/+$'), '')}/embed',
    );

    final http.Response response;
    try {
      response = await _http
          .get(embedUri, headers: _htmlHeaders)
          .timeout(timeout);
    } on TimeoutException {
      throw HikerException('Threads 요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.');
    } catch (error) {
      if (error is HikerException) rethrow;
      throw HikerException('Threads에 연결할 수 없습니다.', detail: '$error');
    }

    if (response.statusCode != 200) {
      final message = switch (response.statusCode) {
        404 => 'Threads 게시물을 찾을 수 없습니다. 삭제되었거나 비공개일 수 있습니다.',
        429 => 'Threads 요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.',
        >= 500 => 'Threads 서버에 일시적인 문제가 있습니다. 잠시 후 다시 시도해 주세요.',
        _ => 'Threads 게시물 조회에 실패했습니다 (HTTP ${response.statusCode}).',
      };
      throw HikerException(message, statusCode: response.statusCode);
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    var post = parseEmbed(
      body,
      code: targetCode,
      fallbackUsername: targetUsername,
    );
    if (post == null || !post.hasDownloadableAssets) {
      throw HikerException(
        '이 Threads 게시물에는 내려받을 사진이나 동영상이 없습니다. '
        '텍스트·링크 전용 게시물일 수 있습니다.',
      );
    }

    // 동영상 등 썸네일이 누락된 항목이 있으면 og:image 메타태그에서 고해상도 썸네일을 보완한다.
    if (post.items.any((item) => item.thumbnailUrl == null)) {
      final ogThumbnail = await _fetchOgThumbnail(targetUri);
      if (ogThumbnail != null) {
        post = post.copyWith(
          items: post.items.map((item) {
            if (item.thumbnailUrl == null) {
              return item.copyWith(thumbnailUrl: ogThumbnail);
            }
            return item;
          }).toList(),
        );
      }
    }

    return post;
  }

  Future<String?> _fetchOgThumbnail(Uri uri) async {
    try {
      final response = await _http
          .get(
            uri,
            headers: const {
              'user-agent':
                  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
              'accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final match = RegExp(
          r'<meta\s+property=["\x27]og:image["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ).firstMatch(response.body);
        if (match != null) {
          final rawUrl = match.group(1);
          if (rawUrl != null && rawUrl.isNotEmpty) {
            final unescaped = rawUrl.replaceAll('&amp;', '&');
            if (_isDownloadUrl(unescaped) &&
                !unescaped.contains('kHwIMM5b8PW')) {
              return unescaped;
            }
          }
        }
      }
    } catch (_) {
      // 썸네일 조회 실패는 전체 게시물 조회를 중단하지 않는다.
    }
    return null;
  }

  /// 링크를 `@user/post/code` 형태의 정식 게시물 주소로 정리한다.
  ///
  /// `/share/` 형태의 공유 링크는 먼저 리디렉션을 따라가 정식 주소를 알아낸다.
  Future<({Uri uri, String code, String? username})> _resolveTarget(
    IgLink link,
  ) async {
    final sourceUrl = link.normalizedUrl ?? link.raw;
    final sourceUri = Uri.tryParse(sourceUrl);
    if (sourceUri == null || link.code == null) {
      throw HikerException('Threads 게시물 주소를 해석하지 못했습니다.');
    }

    Uri targetUri = sourceUri;
    String targetCode = link.code!;
    String? targetUsername = link.username;

    if (sourceUri.pathSegments.contains('share')) {
      try {
        var currentUri = sourceUri;
        for (var i = 0; i < 5; i++) {
          final request = http.Request('GET', currentUri)
            ..followRedirects = false
            ..headers.addAll(_htmlHeaders);
          final streamed = await _http.send(request).timeout(timeout);
          final location = streamed.headers['location'];
          if (location != null && location.isNotEmpty) {
            final nextUri = Uri.parse(location);
            currentUri = nextUri.hasScheme
                ? nextUri
                : currentUri.resolve(location);
            final parsed = IgUrlParser.parse(currentUri.toString());
            if (parsed.code != null) {
              targetCode = parsed.code!;
              targetUsername = parsed.username ?? targetUsername;
            }
            if (parsed.username != null) {
              targetUri = currentUri;
              break;
            }
          } else {
            break;
          }
        }
      } catch (_) {
        // 리디렉션 확인에 실패하면 원래 URI 로 계속 진행한다.
      }
    }

    return (uri: targetUri, code: targetCode, username: targetUsername);
  }

  /// embed 와 게시물 페이지에 쓰는 헤더. UA 에 브라우저 버전을 붙이면 내용 없는
  /// JS 셸이 오므로 이 값을 그대로 쓴다.
  static const _htmlHeaders = {
    'accept': 'text/html,application/xhtml+xml',
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 Safari/537.36',
  };

  /// 게시물 페이지는 탐색 요청으로 보여야 스레드·댓글 데이터를 함께 싣는다.
  static const _pageHeaders = {
    ..._htmlHeaders,
    'sec-fetch-mode': 'navigate',
    'sec-fetch-dest': 'document',
  };

  /// 게시물 페이지에 실린 JSON 에서 본문, 작성자가 이어 단 글, 댓글을 읽는다.
  ///
  /// 로그인 없이 받는 페이지라 댓글은 첫 묶음만 들어 있다. 페이지 구조를 읽지
  /// 못하면 null 을 돌려주고, 호출하는 쪽이 embed 방식으로 물러선다.
  Future<ThreadsThread?> fetchThread(IgLink link) async {
    final target = await _resolveTarget(link);
    final pageUri = Uri(
      scheme: target.uri.scheme,
      host: target.uri.host,
      path: target.uri.path.replaceFirst(RegExp(r'/+$'), ''),
    );
    final response = await _http
        .get(pageUri, headers: _pageHeaders)
        .timeout(timeout);
    if (response.statusCode != 200) return null;

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    return parseThreadPage(body, code: target.code);
  }

  /// 네트워크 없이 게시물 페이지 HTML 을 스레드 트리로 바꾼다.
  static ThreadsThread? parseThreadPage(String html, {required String code}) {
    final rootJson = _findRootJson(html, code);
    if (rootJson == null) return null;
    final root = _toPost(rootJson);
    if (root == null) return null;

    final info = rootJson['text_post_app_info'];
    final nodes = [ThreadNode(post: root, role: ThreadRole.root, depth: 0)];
    final seen = {root.code ?? root.pk};

    void add(Object? json, ThreadRole role, int depth) {
      if (json is! Map<String, dynamic>) return;
      final post = _toPost(json);
      if (post == null || !seen.add(post.code ?? post.pk)) return;
      nodes.add(ThreadNode(post: post, role: role, depth: depth));
    }

    var hasMoreReplies = false;
    if (info is Map<String, dynamic>) {
      // 작성자가 이어서 단 글(1/N …).
      for (final edge in _edges(_at(info, ['self_thread', 'posts']))) {
        add(edge['node'], ThreadRole.continuation, 0);
      }

      // 댓글. 각 묶음의 첫 글이 댓글이고, 뒤따르는 글은 그 댓글에 단 답글이다.
      final replies = info['direct_replies'];
      for (final edge in _edges(replies)) {
        final group = _edges(_at(edge, ['node', 'posts']));
        for (var i = 0; i < group.length; i++) {
          add(group[i]['node'], ThreadRole.reply, i == 0 ? 1 : 2);
        }
      }
      hasMoreReplies = _at(replies, ['page_info', 'has_next_page']) == true;
    }

    return ThreadsThread(nodes: nodes, hasMoreReplies: hasMoreReplies);
  }

  static final _jsonScript = RegExp(
    r'<script type="application/json"[^>]*>(.*?)</script>',
    dotAll: true,
  );

  /// 페이지의 JSON 조각들에서 [code] 게시물을 찾아 스레드·댓글 정보를 붙인다.
  ///
  /// 게시물 본체(`code` 가 있는 객체)와 스레드·댓글 정보는 서로 다른 조각에 실린다.
  /// 후자는 `id`(`<pk>_<작성자 id>`)와 `text_post_app_info` 만 가진 객체라, 본체의
  /// `pk` 로 짝을 찾아 합친다.
  static Map<String, dynamic>? _findRootJson(String html, String code) {
    final decoded = <Object?>[];
    for (final match in _jsonScript.allMatches(html)) {
      final raw = match.group(1)!;
      if (!raw.contains(code) &&
          !raw.contains('"self_thread"') &&
          !raw.contains('"direct_replies"')) {
        continue;
      }
      try {
        decoded.add(jsonDecode(raw));
      } on FormatException {
        continue;
      }
    }

    Map<String, dynamic>? root;
    for (final json in decoded) {
      root = _firstWhere(
        json,
        (map) => map['code'] == code && map['pk'] != null,
      );
      if (root != null) break;
    }
    if (root == null) return null;

    final pk = root['pk'].toString();
    bool hasThread(Object? info) =>
        info is Map<String, dynamic> &&
        (info.containsKey('self_thread') || info.containsKey('direct_replies'));
    bool samePost(Map<String, dynamic> map) {
      final id = (map['pk'] ?? map['id'])?.toString() ?? '';
      return id == pk || id.startsWith('${pk}_');
    }

    for (final json in decoded) {
      final threadHolder = _firstWhere(
        json,
        (map) => samePost(map) && hasThread(map['text_post_app_info']),
      );
      if (threadHolder == null) continue;
      final rootInfo = root['text_post_app_info'];
      return {
        ...root,
        'text_post_app_info': {
          if (rootInfo is Map<String, dynamic>) ...rootInfo,
          ...threadHolder['text_post_app_info'] as Map<String, dynamic>,
        },
      };
    }
    return root;
  }

  static Map<String, dynamic>? _firstWhere(
    Object? json,
    bool Function(Map<String, dynamic> map) test,
  ) {
    if (json is Map<String, dynamic>) {
      if (test(json)) return json;
      for (final value in json.values) {
        final found = _firstWhere(value, test);
        if (found != null) return found;
      }
    } else if (json is List) {
      for (final value in json) {
        final found = _firstWhere(value, test);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Threads 의 미디어 JSON 은 인스타그램과 같은 형태라 [MediaParser] 를 그대로 쓴다.
  /// 동영상 후보에는 해상도가 없어 정렬로는 고를 수 없으니, 가장 좋은 화질이 오는
  /// 첫 후보만 남긴다.
  static IgPost? _toPost(Map<String, dynamic> json) {
    Map<String, dynamic> firstVideoOnly(Map<String, dynamic> media) {
      final versions = media['video_versions'];
      final carousel = media['carousel_media'];
      return {
        ...media,
        if (versions is List && versions.length > 1)
          'video_versions': [versions.first],
        if (carousel is List)
          'carousel_media': [
            for (final child in carousel)
              child is Map<String, dynamic> ? firstVideoOnly(child) : child,
          ],
      };
    }

    return MediaParser.parsePost(
      firstVideoOnly(json),
    )?.copyWith(source: MediaSource.threads);
  }

  static Object? _at(Object? json, List<String> path) {
    Object? current = json;
    for (final key in path) {
      if (current is! Map<String, dynamic>) return null;
      current = current[key];
    }
    return current;
  }

  static List<Map<String, dynamic>> _edges(Object? connection) {
    final edges = _at(connection, ['edges']);
    if (edges is! List) return const [];
    return [
      for (final edge in edges)
        if (edge is Map<String, dynamic>) edge,
    ];
  }

  /// 네트워크 없이 embed HTML을 앱의 공통 게시물 모델로 바꾼다.
  static IgPost? parseEmbed(
    String html, {
    required String code,
    String? fallbackUsername,
  }) {
    final document = html_parser.parse(html);
    final outer = _targetContainer(document);
    if (outer == null) return null;

    final username =
        _nonEmpty(outer.querySelector('.HeaderLink span')?.text) ??
        fallbackUsername ??
        'threads';
    final caption = _nonEmpty(outer.querySelector('.BodyTextContainer')?.text);
    final profilePicUrl = outer
        .querySelector('.AvatarContainer img')
        ?.attributes['src'];
    final isVerified = outer.querySelector('.VerifiedBadge') != null;

    // 링크 미리보기와 인용 게시물의 미디어는 다운로드 대상으로 보지 않고,
    // 현재 게시물의 공식 미디어 컨테이너만 읽는다.
    final mediaRoots = outer
        .querySelectorAll(
          '.SoloMediaContainer, .MediaContainer, .SingleInnerMediaContainer, .SingleInnerMediaContainerVideo',
        )
        .where((element) => _closestOuterContainer(element) == outer);

    final items = <IgItem>[];
    final seen = <String>{};
    for (final root in mediaRoots) {
      for (final element in root.querySelectorAll('img, video')) {
        final isVideo = element.localName == 'video';
        final url = isVideo
            ? element.querySelector('source[src]')?.attributes['src'] ??
                  element.attributes['src']
            : element.attributes['src'];
        if (!_isDownloadUrl(url) || !seen.add(url!)) continue;

        final width = _dimension(element, 'width');
        final height = _dimension(element, 'height');
        final kind = isVideo ? AssetKind.video : AssetKind.photo;
        items.add(
          IgItem(
            id: '$code-${items.length + 1}',
            kind: kind,
            variants: [
              IgAsset(kind: kind, url: url, width: width, height: height),
            ],
            thumbnailUrl: isVideo ? element.attributes['poster'] : url,
          ),
        );
      }
    }

    if (items.isEmpty) return null;
    final kind = items.length > 1
        ? PostKind.carousel
        : (items.single.isVideo ? PostKind.video : PostKind.photo);

    return IgPost(
      pk: code,
      source: MediaSource.threads,
      code: code,
      kind: kind,
      user: IgUser(
        pk: username,
        username: username,
        profilePicUrl: profilePicUrl,
        isVerified: isVerified,
      ),
      caption: caption,
      items: items,
    );
  }

  /// 주소가 가리키는 게시물의 컨테이너를 고른다.
  ///
  /// 댓글(답글)의 embed 에는 부모 글이 위에, 댓글이 아래에 함께 그려진다. 부모는
  /// `BodyContainerParent` 를 품고, 주소가 가리키는 글은 `OuterContainerFull` 이다.
  /// 첫 컨테이너를 그대로 쓰면 댓글을 공유했는데 본문의 미디어를 받게 된다.
  static Element? _targetContainer(Document document) {
    // 인용 게시물은 다른 글 안에 중첩되어 있으므로 최상위 컨테이너만 후보로 본다.
    final containers = document
        .querySelectorAll('.OuterContainer')
        .where((element) => _closestOuterContainer(element.parent) == null)
        .toList();
    if (containers.isEmpty) return null;

    for (final container in containers) {
      if (container.classes.contains('OuterContainerFull')) return container;
    }
    // 표시 클래스가 바뀌더라도 부모 글만은 피한다. 주소의 글은 항상 맨 아래에 온다.
    return containers.lastWhere(
      (container) => container.querySelector('.BodyContainerParent') == null,
      orElse: () => containers.last,
    );
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _isDownloadUrl(String? value) {
    if (value == null || value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }

  static Element? _closestOuterContainer(Element? element) {
    Element? current = element;
    while (current != null) {
      if (current.classes.contains('OuterContainer')) return current;
      current = current.parent;
    }
    return null;
  }

  static int? _dimension(Element element, String name) {
    final direct = int.tryParse(element.attributes[name] ?? '');
    if (direct != null) return direct;
    final style = element.attributes['style'];
    if (style == null) return null;
    final match = RegExp('$name\\s*:\\s*(\\d+)px').firstMatch(style);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  void close() => _http.close();
}
