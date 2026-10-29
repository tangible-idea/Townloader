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
    Future<String?> Function(SavedLink link, {required bool isKo})? title,
    Future<SavedPlace> Function(SavedPlace place)? enrichPlace,
  }) : _store = store,
       _resolve = resolve,
       _analyze = analyze,
       _title = title,
       _enrichPlace = enrichPlace;

  factory LinksController.live(
    IgRepository repository,
    LinkAnalyzer analyzer,
  ) => LinksController(
    store: FileLinksStore(),
    resolve: repository.resolve,
    analyze: analyzer.analyze,
    title: analyzer.title,
    enrichPlace: analyzer.enrichPlace,
  );

  final LinksStore _store;
  final Future<ResolveResult> Function(IgLink link) _resolve;
  final Future<List<SavedPlace>> Function(IgPost post, {required bool isKo})
  _analyze;

  /// 분석이 끝난 글의 대표 제목을 짓는다. 없으면 제목 없이 둔다.
  final Future<String?> Function(SavedLink link, {required bool isKo})? _title;
  final Future<SavedPlace> Function(SavedPlace place)? _enrichPlace;
  bool _titling = false;
  bool _enriching = false;

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

  /// 저장할 때마다 1 씩 늘어난다. 동기화가 바뀐 것이 있는지 볼 때 쓴다.
  int get revision => _revision;
  int _revision = 0;

  LinksData get data => LinksData(categories: _categories, links: _links);

  /// 다른 기기에서 동기화한 링크를 합친다. 같은 글이면 분석이 끝난 쪽을 남기고,
  /// 둘 다 끝났으면 기기의 것을 남긴다. 카테고리는 기기 순서 뒤에 새것을 붙인다.
  Future<void> mergeFrom(LinksData remote) async {
    final byCode = {for (final link in _links) link.code: link};
    var changed = false;
    for (final link in remote.links) {
      final local = byCode[link.code];
      if (local == null ||
          (local.status != LinkStatus.ready && link.status == LinkStatus.ready)) {
        byCode[link.code] = link;
        changed = true;
      } else if (local.title == null && link.title != null) {
        byCode[link.code] = local.copyWith(title: link.title);
        changed = true;
      }
    }
    final categories = [..._categories];
    for (final name in [
      ...remote.categories,
      for (final link in byCode.values) link.category,
    ]) {
      if (name.isNotEmpty && !categories.contains(name)) {
        categories.add(name);
        changed = true;
      }
    }
    if (!changed) return;
    _categories = categories;
    _links = byCode.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    _selected ??= _categories.firstOrNull;
    notifyListeners();
    await _save();
    fillTitles();
  }

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

  /// [text] 에 이 탭에 저장할 수 있는 링크(인스타그램 게시물·릴스)가 있는지.
  static bool hasSavableLink(String text) => extractLinks(text).any((raw) {
    final link = IgUrlParser.parse(raw);
    return (link.type == IgLinkType.post || link.type == IgLinkType.reel) &&
        link.code != null;
  });

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

  /// 글에서 장소 하나를 지운다. 되돌릴 수 있게 지운 자리를 돌려주고, 없으면 -1.
  Future<int> removePlace(String code, SavedPlace place) async {
    final link = _find(code);
    if (link == null) return -1;
    var index = link.places.indexWhere((p) => identical(p, place));
    if (index < 0) {
      index = link.places.indexWhere(
        (p) => p.name == place.name && p.lat == place.lat && p.lng == place.lng,
      );
    }
    if (index < 0) return -1;
    _replace(
      code,
      (l) => l.copyWith(places: [...l.places]..removeAt(index)),
    );
    notifyListeners();
    await _save();
    return index;
  }

  /// [removePlace] 를 되돌린다.
  Future<void> insertPlace(String code, SavedPlace place, int index) async {
    if (_find(code) == null) return;
    _replace(code, (l) {
      final places = [...l.places];
      places.insert(index.clamp(0, places.length), place);
      return l.copyWith(places: places);
    });
    notifyListeners();
    await _save();
  }

  Future<void> moveTo(SavedLink link, String category) async {
    if (!_categories.contains(category)) return;
    _replace(link.code, (l) => l.copyWith(category: category));
    notifyListeners();
    await _save();
  }

  /// 앱을 다시 켰을 때 분석이 끝나지 않았던 글을 다시 돌리고, 제목이 없는 글에 제목을 짓는다.
  void resumePending() {
    for (final link in _links) {
      if (link.status == LinkStatus.failed && link.error == null) {
        retry(link);
      }
    }
    fillTitles();
    fillPlaceDetails();
  }

  /// 예전에 저장해 카카오맵 사진·업종·요약 정보가 없는 장소들을 뒤에서 채운다.
  Future<void> fillPlaceDetails() async {
    final enrich = _enrichPlace;
    if (enrich == null || _enriching) return;
    _enriching = true;
    try {
      for (final link in [..._links]) {
        if (link.status != LinkStatus.ready || link.places.isEmpty) continue;
        if (_enrichedLinks.contains(link.code)) continue;
        if (link.places.every(
          (p) => (p.hasKakaoDetails && p.summary != null) || p.approximate,
        )) {
          _enrichedLinks.add(link.code);
          continue;
        }
        _enrichedLinks.add(link.code);
        final updated = await Future.wait(link.places.map(enrich));
        var changed = false;
        for (var i = 0; i < updated.length; i++) {
          if (!identical(updated[i], link.places[i])) changed = true;
        }
        if (changed) {
          _replace(link.code, (l) => l.copyWith(places: updated));
          notifyListeners();
          await _save();
        }
      }
    } finally {
      _enriching = false;
    }
  }

  final Set<String> _enrichedLinks = {};

  /// 분석은 끝났는데 제목이 없는 글(제목 기능 전에 저장한 글 등)에 하나씩 제목을 짓는다.
  Future<void> fillTitles() async {
    final title = _title;
    if (title == null || _titling) return;
    _titling = true;
    try {
      while (true) {
        final link = _links
            .where((l) => l.status == LinkStatus.ready && l.title == null)
            .where((l) => !_untitled.contains(l.code))
            .firstOrNull;
        if (link == null) break;
        final name = await title(link, isKo: _isKo);
        if (name == null) {
          // 못 지은 글은 이번 실행에서는 다시 묻지 않는다.
          _untitled.add(link.code);
          continue;
        }
        _replace(link.code, (l) => l.copyWith(title: name));
        notifyListeners();
        await _save();
      }
    } finally {
      _titling = false;
    }
  }

  final Set<String> _untitled = {};

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
      final ready = _find(link.code);
      if (ready != null && ready.title == null && _title != null) {
        final name = await _title(ready, isKo: _isKo);
        if (name != null) _replace(link.code, (l) => l.copyWith(title: name));
      }
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

  Future<void> _save() {
    _revision++;
    return _store.save(LinksData(categories: _categories, links: _links));
  }
}
