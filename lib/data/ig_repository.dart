import '../l10n/strings.dart';
import '../models/ig_post.dart';
import '../models/ig_user.dart';
import '../models/threads_thread.dart';
import 'hiker_client.dart';
import 'ig_url.dart';
import 'media_parser.dart';
import 'threads_client.dart';

/// 링크 하나를 해석한 결과. 스토리처럼 여러 건이 나오는 경우가 있어 항상 목록이다.
class ResolveResult {
  const ResolveResult({
    required this.title,
    required this.posts,
    this.user,
    this.thread,
  });

  /// 결과 화면 상단에 보여줄 한 줄 설명.
  final String title;
  final List<IgPost> posts;
  final IgUser? user;

  /// Threads 게시물에 이어지는 글이나 댓글이 있으면 트리로 담긴다. 이때 [posts] 는
  /// 본문(작성자 글) 중 미디어가 있는 것들이다.
  final ThreadsThread? thread;

  bool get isEmpty => posts.isEmpty;
}

/// 커서 기반 목록 응답 한 페이지.
class MediaPage {
  const MediaPage({required this.posts, this.nextCursor});

  final List<IgPost> posts;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// 링크 종류에 맞는 HikerAPI 엔드포인트를 골라 호출하고 모델로 돌려준다.
class IgRepository {
  IgRepository(this._client, {ThreadsClient? threadsClient})
    : _threadsClient = threadsClient ?? ThreadsClient();

  final HikerClient _client;
  final ThreadsClient _threadsClient;

  Future<ResolveResult> resolve(IgLink link) async {
    return switch (link.type) {
      IgLinkType.post || IgLinkType.reel => _resolveMediaByCode(link.code!),
      IgLinkType.share => _resolveShareLink(link),
      IgLinkType.shareToken => _resolveShareToken(link),
      IgLinkType.story => _resolveStory(link),
      IgLinkType.userStories => _resolveUserStories(link.username!),
      IgLinkType.highlight => _resolveHighlight(link),
      IgLinkType.profile => throw HikerException('프로필 링크입니다. 프로필 탭에서 열어 주세요.'),
      IgLinkType.threadsPost => _resolveThreadsPost(link),
      IgLinkType.threadsProfile => throw HikerException(
        'Threads 프로필 링크입니다. 개별 게시물 주소를 붙여넣어 주세요.',
      ),
      IgLinkType.unknown => throw HikerException(
        '인스타그램 또는 Threads 게시물 주소를 붙여넣어 주세요.',
      ),
    };
  }

  Future<ResolveResult> _resolveThreadsPost(IgLink link) async {
    // 게시물 페이지에서 이어지는 글·댓글까지 읽어 본다. 실패하거나 단독 게시물이면
    // 검증된 embed 방식으로 한 게시물만 가져온다.
    ThreadsThread? thread;
    try {
      thread = await _threadsClient.fetchThread(link);
    } catch (_) {
      thread = null;
    }
    if (thread != null && !thread.isSinglePost) {
      final root = thread.root;
      return ResolveResult(
        title: '@${root.authorName} · Threads · ${S.current.threadLabel}',
        posts: thread.mainPosts,
        user: root.user,
        thread: thread,
      );
    }

    final post = await _threadsClient.fetchPost(link);
    return ResolveResult(
      title:
          '@${post.authorName} · Threads · ${post.kind.localizedLabel(S.current.isKo)}',
      posts: [post],
      user: post.user,
    );
  }

  // ── 게시물 ────────────────────────────────────────────────────────────────

  /// 단축코드로 게시물을 가져온다.
  ///
  /// v1 은 광고 게시물과 캐러셀 자식(`resources`)까지 돌려주므로 이쪽을 먼저 쓰고,
  /// v1 이 실패할 때만 v2 로 한 번 더 시도한다.
  Future<ResolveResult> _resolveMediaByCode(String code) async {
    Map<String, dynamic>? raw;
    try {
      raw = _asMap(
        await _client.get('/v1/media/by/code', query: {'code': code}),
      );
    } on HikerException catch (error) {
      if (!error.isNotFound) rethrow;
      raw = _asMap(
        await _client.get('/v2/media/info/by/code', query: {'code': code}),
      );
    }

    final post = MediaParser.parsePost(raw);
    if (post == null || !post.hasDownloadableAssets) {
      throw HikerException('이 게시물에서 내려받을 수 있는 파일을 찾지 못했습니다.');
    }
    return ResolveResult(
      title:
          '@${post.authorName} · ${post.kind.localizedLabel(S.current.isKo)}',
      posts: [post],
      user: post.user,
    );
  }

  /// `instagram.com/share/...` 형태의 게시물 단축 링크.
  /// 서버가 리디렉션을 따라가 주므로 URL 을 그대로 넘긴다.
  Future<ResolveResult> _resolveShareLink(IgLink link) async {
    final url = link.normalizedUrl ?? link.raw;
    final raw = _asMap(
      await _client.get('/v1/media/by/url', query: {'url': url}),
    );
    final post = MediaParser.parsePost(raw);
    if (post == null || !post.hasDownloadableAssets) {
      throw HikerException('공유 링크에서 게시물을 찾지 못했습니다. 원본 게시물 주소로 다시 시도해 주세요.');
    }
    return ResolveResult(
      title:
          '@${post.authorName} · ${post.kind.localizedLabel(S.current.isKo)}',
      posts: [post],
      user: post.user,
    );
  }

  /// `/s/<token>` 링크는 먼저 무엇을 가리키는지 물어본 뒤 다시 분기한다.
  /// 응답은 `{"pk": ..., "type": "highlight"}` 형태다.
  Future<ResolveResult> _resolveShareToken(IgLink link) async {
    final url = link.normalizedUrl ?? link.raw;
    final raw = _asMap(
      await _client.get('/v1/share/by/url', query: {'url': url}),
    );
    final pk = raw?['pk']?.toString();
    final type = (raw?['type'] as String?)?.toLowerCase();

    if (pk == null || pk.isEmpty) {
      throw HikerException('이 공유 링크를 해석하지 못했습니다.');
    }

    if (type == 'highlight') {
      return _resolveHighlightById(pk);
    }
    if (type == 'story') {
      final story = _asMap(
        await _client.get('/v1/story/by/id', query: {'id': pk}),
      );
      return _storiesResult([story], fallbackTitle: S.current.stories);
    }
    // 그 외 타입은 일반 게시물로 간주한다.
    final media = _asMap(
      await _client.get('/v1/media/by/id', query: {'id': pk}),
    );
    final post = MediaParser.parsePost(media);
    if (post == null || !post.hasDownloadableAssets) {
      throw HikerException('이 공유 링크에서 내려받을 수 있는 파일을 찾지 못했습니다.');
    }
    return ResolveResult(
      title:
          '@${post.authorName} · ${post.kind.localizedLabel(S.current.isKo)}',
      posts: [post],
      user: post.user,
    );
  }

  // ── 스토리 / 하이라이트 ────────────────────────────────────────────────────

  Future<ResolveResult> _resolveStory(IgLink link) async {
    final url = link.normalizedUrl ?? link.raw;
    final raw = _asMap(
      await _client.get('/v1/story/by/url', query: {'url': url}),
    );
    return _storiesResult([raw], fallbackTitle: S.current.stories);
  }

  Future<ResolveResult> _resolveUserStories(String username) async {
    final raw = await _client.get(
      '/v1/user/stories/by/username',
      query: {'username': username},
    );
    final stories = raw is List ? raw : const [];
    if (stories.isEmpty) {
      throw HikerException('@$username 에 현재 올라와 있는 스토리가 없습니다.');
    }
    return _storiesResult(
      stories,
      fallbackTitle: S.current.userStories(username),
    );
  }

  Future<ResolveResult> _resolveHighlight(IgLink link) async {
    final id = link.highlightId;
    if (id != null) return _resolveHighlightById(id);

    final url = link.normalizedUrl ?? link.raw;
    final raw = await _client.get('/v1/highlight/by/url', query: {'url': url});
    return _highlightResult(raw);
  }

  Future<ResolveResult> _resolveHighlightById(String pk) async {
    // 하이라이트 id 는 `highlight:<pk>` 형태를 요구하는 엔드포인트가 있어 둘 다 시도한다.
    final normalized = pk.startsWith('highlight:') ? pk : 'highlight:$pk';
    final raw = await _client.get(
      '/v1/highlight/by/url',
      query: {
        'url':
            'https://www.instagram.com/stories/highlights/'
            '${normalized.split(':').last}/',
      },
    );
    return _highlightResult(raw);
  }

  /// 하이라이트 응답은 `items` 안에 스토리 목록이 들어 있다.
  ResolveResult _highlightResult(dynamic raw) {
    final map = _asMap(raw);
    final items = map?['items'] ?? map?['media'] ?? raw;
    final list = items is List ? items : (map == null ? const [] : [map]);
    final title = (map?['title'] as String?)?.trim();
    return _storiesResult(list, fallbackTitle: S.current.highlight(title));
  }

  ResolveResult _storiesResult(
    Iterable<dynamic> raw, {
    required String fallbackTitle,
  }) {
    final posts = MediaParser.parsePosts(raw);
    if (posts.isEmpty) {
      throw HikerException('내려받을 수 있는 스토리를 찾지 못했습니다. 이미 만료되었을 수 있습니다.');
    }
    final user = posts.first.user;
    final owner = user == null
        ? fallbackTitle
        : '@${user.username} · $fallbackTitle';
    return ResolveResult(
      title: '$owner · ${S.current.itemCountShort(posts.length)}',
      posts: posts,
      user: user,
    );
  }

  // ── 프로필 ────────────────────────────────────────────────────────────────

  Future<IgUser> fetchUser(String username) async {
    final raw = _asMap(
      await _client.get('/v1/user/by/username', query: {'username': username}),
    );
    final user = IgUser.fromJson(raw);
    if (user == null) throw HikerException('@$username 계정을 찾지 못했습니다.');
    return user;
  }

  Future<List<IgPost>> fetchUserStories(String username) async {
    final raw = await _client.get(
      '/v1/user/stories/by/username',
      query: {'username': username},
    );
    return MediaParser.parsePosts(raw is List ? raw : const []);
  }

  /// 프로필 피드 한 페이지. [cursor] 가 null 이면 첫 페이지다.
  Future<MediaPage> fetchUserMedias(String userId, {String? cursor}) {
    return _fetchChunk('/v1/user/medias/chunk', userId, cursor);
  }

  /// 릴스만 모아 보는 페이지.
  Future<MediaPage> fetchUserClips(String userId, {String? cursor}) {
    return _fetchChunk('/v1/user/clips/chunk', userId, cursor);
  }

  Future<MediaPage> _fetchChunk(
    String path,
    String userId,
    String? cursor,
  ) async {
    final raw = await _client.get(
      path,
      query: {'user_id': userId, 'end_cursor': cursor},
    );

    // chunk 계열은 `[[미디어들], "다음커서"]` 형태로 돌아온다.
    if (raw is List) {
      final medias = raw.isNotEmpty && raw.first is List
          ? raw.first as List
          : const [];
      final next = raw.length > 1 ? raw[1]?.toString() : null;
      return MediaPage(
        posts: MediaParser.parsePosts(medias),
        nextCursor: (next == null || next.isEmpty || next == 'null')
            ? null
            : next,
      );
    }

    // 혹시 맵으로 오는 변형이 있으면 그것도 받아 준다.
    final map = _asMap(raw);
    final medias = map?['medias'] ?? map?['response'] ?? const [];
    final next = map?['next_page_id'] ?? map?['end_cursor'];
    return MediaPage(
      posts: MediaParser.parsePosts(medias is List ? medias : const []),
      nextCursor: next?.toString(),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return null;
  }
}
