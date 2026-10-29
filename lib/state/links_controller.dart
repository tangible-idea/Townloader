import 'package:flutter/foundation.dart';

import '../data/hiker_client.dart';
import '../data/ig_repository.dart';
import '../data/ig_url.dart';
import '../data/places_client.dart';
import '../models/ig_post.dart';
import '../models/saved_link.dart';
import '../services/link_analyzer.dart';
import '../services/links_store.dart';

/// 붙여넣은 글자에서 링크를 저장한 결과.
typedef AddLinksResult = ({int added, int duplicates, int unsupported});

/// Links 탭: 카테고리별로 저장한 글과, 글마다 찾은 장소.
///
/// 링크를 붙여넣으면 바로 목록에 넣고, 뒤에서 한 개씩 글을 불러와 장소를 찾는다.
class LinksController extends ChangeNotifier {
  LinksController({
    required LinksStore store,
    required Future<ResolveResult> Function(IgLink link) resolve,
    required Future<List<SavedPlace>> Function(
      IgPost post, {
      required bool isKo,
    })
    analyze,
  }) : _store = store,
       _resolve = resolve,
       _analyze = analyze;

  factory LinksController.live(
    IgRepository repository,
    LinkAnalyzer analyzer,
  ) => LinksController(
    store: FileLinksStore(),
    resolve: repository.resolve,
    analyze: analyzer.analyze,
  );

  final LinksStore _store;
  final Future<ResolveResult> Function(IgLink link) _resolve;
  final Future<List<SavedPlace>> Function(IgPost post, {required bool isKo})
  _analyze;

  List<String> _categories = const [];
  List<SavedLink> _links = const [];
  String? _selected;
  bool _loaded = false;

  /// 분석을 기다리는 글의 코드. 한 번에 하나씩 처리한다.
  final List<String> _queue = [];
  bool _working = false;
  bool _isKo = true;

  bool get isLoaded => _loaded;
  List<String> get categories => _categories;

  /// 지금 보고 있고, 붙여넣은 링크가 들어갈 카테고리.
  String? get selectedCategory => _selected;

  /// 지금 카테고리의 글. 최근에 저장한 것이 위로 온다.
  List<SavedLink> get links => [
    for (final link in _links)
      if (link.category == _selected) link,
  ];

  List<SavedLink> get allLinks => _links;

  int countIn(String category) =>
      _links.where((link) => link.category == category).length;

  Future<void> load({required bool isKo}) async {
    _isKo = isKo;
    final data = await _store.load();
    _categories = data?.categories.isNotEmpty == true
        ? data!.categories
        : (isKo ? const ['여행', '맛집'] : const ['Travel', 'Food']);
    _links = data?.links ?? const [];
    _selected = _categories.first;
    _loaded = true;
    notifyListeners();
  }

  void selectCategory(String category) {
    if (!_categories.contains(category) || category == _selected) return;
    _selected = category;
    notifyListeners();
  }

  /// 새 카테고리를 만들고 고른다. 이미 있으면 그것을 고른다.
  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (!_categories.contains(trimmed)) {
      _categories = [..._categories, trimmed];
    }
    _selected = trimmed;
    notifyListeners();
    await _save();
  }

  /// [text] 안의 인스타그램 게시물·릴스 링크를 모두 지금 카테고리에 저장한다.
  Future<AddLinksResult> addFromText(String text, {required bool isKo}) async {
    _isKo = isKo;
    final category = _selected;
    if (category == null) return (added: 0, duplicates: 0, unsupported: 0);

    var added = 0;
    var duplicates = 0;
    var unsupported = 0;
    final known = {for (final link in _links) link.code};
    final fresh = <SavedLink>[];
    for (final raw in extractLinks(text)) {
      final link = IgUrlParser.parse(raw);
      final code = link.code;
      if ((link.type != IgLinkType.post && link.type != IgLinkType.reel) ||
          code == null) {
        unsupported++;
        continue;
      }
      if (!known.add(code)) {
        duplicates++;
        continue;
      }
      fresh.add(
        SavedLink(
          code: code,
          url: link.normalizedUrl ?? 'https://www.instagram.com/p/$code/',
          category: category,
          savedAt: DateTime.now(),
        ),
      );
      added++;
    }
    if (fresh.isEmpty) {
      return (added: 0, duplicates: duplicates, unsupported: unsupported);
    }

    _links = [...fresh.reversed, ..._links];
    _queue.addAll(fresh.map((link) => link.code));
    notifyListeners();
    await _save();
    _pump();
    return (added: added, duplicates: duplicates, unsupported: unsupported);
  }

  /// 붙여넣은 글자에서 인스타그램 주소만 뽑는다. 여러 줄, 공백, 다른 글이 섞여도 된다.
  static List<String> extractLinks(String text) => [
    for (final match in RegExp(
      r'(?:https?://)?(?:www\.|m\.)?instagram\.com/[^\s<>"]+',
      caseSensitive: false,
    ).allMatches(text))
      match.group(0)!,
  ];

  Future<void> retry(SavedLink link) async {
    _replace(
      link.code,
      (l) => l.copyWith(status: LinkStatus.analyzing, clearError: true),
    );
    if (!_queue.contains(link.code)) _queue.add(link.code);
    notifyListeners();
    _pump();
  }

  Future<void> remove(SavedLink link) async {
    _queue.remove(link.code);
    _links = [
      for (final l in _links)
        if (l.code != link.code) l,
    ];
    notifyListeners();
    await _save();
  }

  Future<void> moveTo(SavedLink link, String category) async {
    if (!_categories.contains(category)) return;
    _replace(link.code, (l) => l.copyWith(category: category));
    notifyListeners();
    await _save();
  }

  /// 앱을 다시 켰을 때 분석이 끝나지 않았던 글을 다시 돌린다.
  void resumePending() {
    for (final link in _links) {
      if (link.status == LinkStatus.failed && link.error == null) {
        retry(link);
      }
    }
  }

  Future<void> _pump() async {
    if (_working) return;
    _working = true;
    try {
      while (_queue.isNotEmpty) {
        final code = _queue.removeAt(0);
        final link = _find(code);
        if (link == null) continue;
        await _process(link);
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _process(SavedLink link) async {
    try {
      final result = await _resolve(IgUrlParser.parse(link.url));
      final post = result.posts.isEmpty ? null : result.posts.first;
      if (post == null) throw PlacesException('게시물을 불러오지 못했습니다.');

      // 글 정보를 먼저 보여 주고, 장소는 찾는 대로 채운다.
      _replace(
        link.code,
        (l) => l.copyWith(
          author: post.authorName,
          caption: post.caption,
          coverUrl: post.coverUrl,
          imageUrls: LinkAnalyzer.imageUrlsOf(post),
        ),
      );
      notifyListeners();

      final places = await _analyze(post, isKo: _isKo);
      _replace(
        link.code,
        (l) => l.copyWith(
          status: LinkStatus.ready,
          places: places,
          clearError: true,
        ),
      );
    } on HikerException catch (error) {
      _fail(link, error.message);
    } on PlacesException catch (error) {
      _fail(link, error.message);
    } catch (error) {
      _fail(link, error.toString());
    }
    notifyListeners();
    await _save();
  }

  void _fail(SavedLink link, String message) => _replace(
    link.code,
    (l) => l.copyWith(status: LinkStatus.failed, error: message),
  );

  SavedLink? _find(String code) {
    for (final link in _links) {
      if (link.code == code) return link;
    }
    return null;
  }

  void _replace(String code, SavedLink Function(SavedLink link) update) {
    _links = [for (final l in _links) l.code == code ? update(l) : l];
  }

  Future<void> _save() =>
      _store.save(LinksData(categories: _categories, links: _links));
}
