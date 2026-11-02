import '../models/media_source.dart';

/// 사용자가 붙여넣은 문자열이 무엇을 가리키는지 판정한 결과.
enum IgLinkType {
  /// `/p/<code>/` — 사진 또는 캐러셀 게시물.
  post,

  /// `/reel/<code>/`, `/reels/<code>/`, `/tv/<code>/` — 릴스와 IGTV.
  reel,

  /// `/share/<code>` 또는 `/share/reel/<code>` — 앱에서 복사한 게시물 단축 링크.
  share,

  /// `/s/<token>` — 스토리·하이라이트를 가리키는 인코딩 링크.
  /// 무엇을 가리키는지는 서버에 물어봐야 알 수 있다.
  shareToken,

  /// `/stories/<username>/<id>/` — 스토리 한 개.
  story,

  /// `/stories/<username>/` — 해당 계정의 현재 스토리 전체.
  userStories,

  /// `/stories/highlights/<id>/` 또는 `/s/<token>` — 하이라이트.
  highlight,

  /// `/<username>/` 또는 `@username` — 프로필.
  profile,

  /// `threads.com/@<username>/post/<code>` 또는 `threads.com/t/<code>` — Threads 게시물.
  threadsPost,

  /// `threads.com/@<username>` — Threads 프로필.
  threadsProfile,

  unknown,
}

class IgLink {
  const IgLink({
    required this.type,
    required this.raw,
    this.code,
    this.username,
    this.storyId,
    this.highlightId,
    this.normalizedUrl,
  });

  final IgLinkType type;

  /// 사용자가 입력한 원본 문자열.
  final String raw;

  /// 게시물 단축코드 (`DcMXl1IPNtB` 같은 값).
  final String? code;
  final String? username;

  /// 스토리의 숫자 pk.
  final String? storyId;
  final String? highlightId;

  /// HikerAPI 의 `by/url` 계열 엔드포인트에 넘길 정규화된 주소.
  final String? normalizedUrl;

  bool get isKnown => type != IgLinkType.unknown;

  /// 이 링크를 어느 서비스에서 조회해야 하는지.
  MediaSource get source => switch (type) {
    IgLinkType.threadsPost || IgLinkType.threadsProfile => MediaSource.threads,
    _ => MediaSource.instagram,
  };
}

/// 인스타그램 링크·단축코드·사용자명 문자열을 [IgLink] 로 해석한다.
///
/// 브라우저 주소창에서 복사한 주소, 앱의 공유 링크, `@handle`, 단축코드만 붙여넣은
/// 경우까지 모두 받는다. 네트워크를 타지 않고 문자열만 본다.
class IgUrlParser {
  IgUrlParser._();

  /// 인스타그램·Threads 단축코드에 쓰이는 문자 집합(base64url 계열)과 길이 범위.
  static final RegExp _shortcode = RegExp(r'^[A-Za-z0-9_-]{5,35}$');
  static final RegExp _username = RegExp(r'^[A-Za-z0-9._]{1,30}$');
  static final RegExp _digits = RegExp(r'^\d+$');

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  );

  static final RegExp _bareUrlRegex = RegExp(
    r'(?:[a-zA-Z0-9-]+\.)*(?:threads\.(?:com|net)|instagram\.com|instagr\.am|ig\.me)/[^\s<>"]*',
    caseSensitive: false,
  );

  /// 프로필로 오인하기 쉬운 인스타그램 자체 경로들.
  static const _reservedPaths = {
    'explore',
    'accounts',
    'directs',
    'direct',
    'about',
    'developer',
    'legal',
    'privacy',
    'terms',
    'sessions',
    'challenge',
    'graphql',
    'api',
    'web',
    'oauth',
    'emails',
    'ajax',
    'push',
    'qr',
    'lite',
    'your_activity',
    'reels_audio',
  };

  static IgLink parse(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return IgLink(type: IgLinkType.unknown, raw: raw);

    // 텍스트 사이에 URL 이 섞여 있는 경우(메신저 공유 문구 등) URL 만 먼저 추출한다.
    final urlMatch = _urlRegex.firstMatch(raw) ?? _bareUrlRegex.firstMatch(raw);
    if (urlMatch != null) {
      raw = urlMatch.group(0)!.replaceAll(RegExp(r'[),.;!?]+$'), '');
    }

    // `@handle` 형태는 링크가 아니라 프로필 지정으로 본다.
    if (raw.startsWith('@')) {
      final name = raw.substring(1).trim();
      if (_username.hasMatch(name)) {
        return IgLink(
          type: IgLinkType.profile,
          raw: raw,
          username: name.toLowerCase(),
        );
      }
      return IgLink(type: IgLinkType.unknown, raw: raw);
    }

    final uri = _tryParseUri(raw);
    if (uri == null) return _parseBareToken(raw);
    if (_isThreadsHost(uri.host)) return _parseThreads(uri, raw);
    if (!_isInstagramHost(uri.host)) {
      return IgLink(type: IgLinkType.unknown, raw: raw);
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return IgLink(type: IgLinkType.unknown, raw: raw);

    final first = segments.first.toLowerCase();

    switch (first) {
      case 'p':
      case 'tv':
      case 'reel':
      case 'reels':
        final code = segments.length > 1 ? segments[1] : null;
        if (code == null || !_shortcode.hasMatch(code)) {
          return IgLink(type: IgLinkType.unknown, raw: raw);
        }
        // `/reels/<code>/` 는 릴스 단건, `/reels/audio/...` 등은 게시물이 아니다.
        final isReel = first != 'p';
        return IgLink(
          type: isReel ? IgLinkType.reel : IgLinkType.post,
          raw: raw,
          code: code,
          normalizedUrl:
              'https://www.instagram.com/${isReel ? 'reel' : 'p'}/$code/',
        );

      case 'share':
        // `/share/reel/<code>`, `/share/p/<code>`, `/share/<code>` 를 모두 받는다.
        final tail = segments.sublist(1);
        final code = tail.isEmpty ? null : tail.last;
        if (code == null || !_shortcode.hasMatch(code)) {
          return IgLink(type: IgLinkType.unknown, raw: raw);
        }
        return IgLink(
          type: IgLinkType.share,
          raw: raw,
          code: code,
          normalizedUrl: uri.replace(query: '', fragment: '').toString(),
        );

      case 'stories':
        if (segments.length >= 2 && segments[1].toLowerCase() == 'highlights') {
          final id = segments.length > 2 ? segments[2] : null;
          if (id == null || !_digits.hasMatch(id)) {
            return IgLink(type: IgLinkType.unknown, raw: raw);
          }
          return IgLink(type: IgLinkType.highlight, raw: raw, highlightId: id);
        }
        final user = segments.length > 1 ? segments[1] : null;
        if (user == null || !_username.hasMatch(user)) {
          return IgLink(type: IgLinkType.unknown, raw: raw);
        }
        final storyId = segments.length > 2 ? segments[2] : null;
        if (storyId != null && _digits.hasMatch(storyId)) {
          return IgLink(
            type: IgLinkType.story,
            raw: raw,
            username: user.toLowerCase(),
            storyId: storyId,
            normalizedUrl: 'https://www.instagram.com/stories/$user/$storyId/',
          );
        }
        return IgLink(
          type: IgLinkType.userStories,
          raw: raw,
          username: user.toLowerCase(),
        );

      case 's':
        if (segments.length < 2) {
          return IgLink(type: IgLinkType.unknown, raw: raw);
        }
        return IgLink(
          type: IgLinkType.shareToken,
          raw: raw,
          normalizedUrl: uri.replace(query: '', fragment: '').toString(),
        );

      default:
        if (_reservedPaths.contains(first) || !_username.hasMatch(first)) {
          return IgLink(type: IgLinkType.unknown, raw: raw);
        }
        // `/<username>/reels/` 같은 하위 탭도 프로필로 취급한다.
        return IgLink(
          type: IgLinkType.profile,
          raw: raw,
          username: first.toLowerCase(),
        );
    }
  }

  /// threads.com / threads.net 주소를 해석한다.
  ///
  /// Threads 는 게시물 주소 뒤에 캡션에서 만든 슬러그를 덧붙이는데
  /// (`/@user/post/<code>/turn-a-thread-into-an-image`), 슬러그는 의미가 없으므로
  /// 버리고 단축코드만 남긴다.
  static IgLink _parseThreads(Uri uri, String raw) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return IgLink(type: IgLinkType.unknown, raw: raw);

    final first = segments.first.toLowerCase();

    // `/t/<code>` 는 앱의 공유 단축 링크로, 서버가 정식 주소로 리디렉션해 준다.
    if (first == 't') {
      final code = segments.length > 1 ? segments[1] : null;
      if (code == null || !_shortcode.hasMatch(code)) {
        return IgLink(type: IgLinkType.unknown, raw: raw);
      }
      return IgLink(
        type: IgLinkType.threadsPost,
        raw: raw,
        code: code,
        normalizedUrl: 'https://www.threads.com/t/$code',
      );
    }

    // `/share/<code>` 는 앱의 공유 링크.
    if (first == 'share') {
      final tail = segments.sublist(1);
      final code = tail.isEmpty ? null : tail.last;
      if (code == null || !_shortcode.hasMatch(code)) {
        return IgLink(type: IgLinkType.unknown, raw: raw);
      }
      return IgLink(
        type: IgLinkType.threadsPost,
        raw: raw,
        code: code,
        normalizedUrl: 'https://www.threads.com/share/$code',
      );
    }

    // `/post/<code>`
    if (first == 'post') {
      final code = segments.length > 1 ? segments[1] : null;
      if (code == null || !_shortcode.hasMatch(code)) {
        return IgLink(type: IgLinkType.unknown, raw: raw);
      }
      return IgLink(
        type: IgLinkType.threadsPost,
        raw: raw,
        code: code,
        normalizedUrl: 'https://www.threads.com/post/$code',
      );
    }

    final hasAt = segments.first.startsWith('@');
    final username = hasAt
        ? segments.first.substring(1).toLowerCase()
        : segments.first.toLowerCase();

    if (_reservedPaths.contains(username) || !_username.hasMatch(username)) {
      return IgLink(type: IgLinkType.unknown, raw: raw);
    }

    final isPost = segments.length > 2 && segments[1].toLowerCase() == 'post';
    if (!isPost) {
      if (!hasAt) {
        return IgLink(type: IgLinkType.unknown, raw: raw);
      }
      return IgLink(
        type: IgLinkType.threadsProfile,
        raw: raw,
        username: username,
      );
    }

    final code = segments[2];
    if (!_shortcode.hasMatch(code)) {
      return IgLink(type: IgLinkType.unknown, raw: raw);
    }
    return IgLink(
      type: IgLinkType.threadsPost,
      raw: raw,
      code: code,
      username: username,
      normalizedUrl: 'https://www.threads.com/@$username/post/$code',
    );
  }

  /// 주소가 아니라 단축코드나 사용자명만 붙여넣은 경우를 처리한다.
  static IgLink _parseBareToken(String raw) {
    if (raw.contains('/') || raw.contains(' ')) {
      return IgLink(type: IgLinkType.unknown, raw: raw);
    }
    // 단축코드와 사용자명은 문자 집합이 겹친다. `.`/`_` 만 쓸 수 있는 사용자명과
    // 달리 코드에는 `-` 가 쓰이고, 코드 길이는 보통 11자다. 애매하면 게시물로 본다.
    if (_shortcode.hasMatch(raw) && (raw.length == 11 || raw.contains('-'))) {
      return IgLink(
        type: IgLinkType.post,
        raw: raw,
        code: raw,
        normalizedUrl: 'https://www.instagram.com/p/$raw/',
      );
    }
    if (_username.hasMatch(raw)) {
      return IgLink(
        type: IgLinkType.profile,
        raw: raw,
        username: raw.toLowerCase(),
      );
    }
    return IgLink(type: IgLinkType.unknown, raw: raw);
  }

  /// 스킴 없이 붙여넣어도 주소로 볼 수 있는 도메인들.
  static const _bareHostHints = ['instagram.com', 'threads.com', 'threads.net'];

  static Uri? _tryParseUri(String raw) {
    final hasScheme = raw.startsWith('http://') || raw.startsWith('https://');
    final looksLikeHost = _bareHostHints.any(raw.contains);
    final withScheme = hasScheme ? raw : (looksLikeHost ? 'https://$raw' : raw);
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  static bool _isInstagramHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'instagram.com' ||
        normalized.endsWith('.instagram.com') ||
        normalized == 'instagr.am' ||
        normalized.endsWith('.instagr.am') ||
        normalized == 'ig.me';
  }

  /// Threads 는 threads.net 에서 threads.com 으로 옮겨 갔고 두 도메인이 모두 살아 있다.
  static bool _isThreadsHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'threads.com' ||
        normalized.endsWith('.threads.com') ||
        normalized == 'threads.net' ||
        normalized.endsWith('.threads.net');
  }
}
