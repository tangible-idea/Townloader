import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/strings.dart';
import '../models/saved_link.dart';
import '../state/links_controller.dart';
import 'map/place_card_image.dart';
import 'widgets/network_thumb.dart';
import 'widgets/state_views.dart';

/// 저장한 모든 장소를 지구본 위에 한 번에 보여 준다. 카테고리는 점 색으로 나눈다.
///
/// 모든 장소에 작은 점을 찍고, 자리가 나는 곳에는 사진 카드를 띄운다(겹치면 Mapbox 가
/// 알아서 숨기고, 확대할수록 더 많이 보인다). 아래 카드를 넘기면 그 장소로 날아간다.
///
/// 한 번에 한 카테고리만 보여 주고, 그 안의 글마다 점 색을 다르게 한다.
/// [links] 를 주면 내 Links 대신 그 글들을 그린다(공유받은 지도).
class PlacesMapScreen extends StatefulWidget {
  const PlacesMapScreen({
    super.key,
    this.links,
    this.category,
    this.title,
    this.initialLink,
    this.initialPlace,
  });

  final List<SavedLink>? links;

  /// 보여 줄 카테고리. 없으면 [links] 를 모두 그린다.
  final String? category;
  final String? title;

  /// 처음 열 때 맞춰 보여 줄 글. 지정하면 이 글의 장소들로 날아가고 아래 카드도
  /// 이 글의 장소부터 시작한다.
  final SavedLink? initialLink;

  /// 처음 열 때 바로 가리킬 장소.
  final SavedPlace? initialPlace;

  /// [link] 를 주면 그 글의 카테고리를, 아니면 [category] 를 연다.
  static Future<void> open(
    BuildContext context, {
    String? category,
    SavedLink? link,
    SavedPlace? place,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlacesMapScreen(
        category: link?.category ?? category,
        initialLink: link,
        initialPlace: place,
      ),
    ),
  );

  /// 글마다 돌려 쓰는 점 색. 밝은 지도 위에서 서로 구분되도록 고른 색이다.
  static const List<int> itemColors = [
    0xFF0B7A5E, // 초록
    0xFFE8590C, // 주황
    0xFF1C7ED6, // 파랑
    0xFFD6336C, // 분홍
    0xFF7048E8, // 보라
    0xFFF08C00, // 노랑
    0xFF0C8599, // 청록
    0xFF5C3B1E, // 갈색
  ];

  static int colorAt(int index) => itemColors[index % itemColors.length];

  @override
  State<PlacesMapScreen> createState() => _PlacesMapScreenState();
}

/// 지도에 찍을 장소 하나와 그 장소를 찾은 글.
class _Pin {
  const _Pin(this.place, this.link);

  final SavedPlace place;
  final SavedLink link;

  Point get point => Point(coordinates: Position(place.lng, place.lat));
}

class _PlacesMapScreenState extends State<PlacesMapScreen> {
  late final List<_Pin> _pins = [
    for (final link
        in widget.links ?? context.read<LinksController>().allLinks)
      if (widget.category == null || link.category == widget.category)
        for (final place in link.places) _Pin(place, link),
  ];

  /// 처음 그릴 때의 글 순서. 장소를 지워도 남은 글의 색이 바뀌지 않게 고정한다.
  late final List<String> _linkOrder = {
    for (final pin in _pins) pin.link.code,
  }.toList();

  /// 내 장소를 보고 있을 때만 지울 수 있다. 공유받은 지도는 보기만 한다.
  bool get _editable => widget.links == null;

  /// 장소가 하나라도 남은 글. 범례에 보인다. 장소를 지우면 줄어든다.
  List<SavedLink> get _legendLinks {
    final seen = <String>{};
    return [
      for (final pin in _pins)
        if (seen.add(pin.link.code)) pin.link,
    ];
  }

  int _colorOf(SavedLink link) =>
      PlacesMapScreen.colorAt(math.max(0, _linkOrder.indexOf(link.code)));

  /// 범례와 카드에 쓰는 글 이름. 대표 제목, 없으면 계정명.
  static String _nameOf(SavedLink link) =>
      link.title ?? (link.author == null ? link.code : '@${link.author}');
  final _cards = PlaceCardImage();
  late final int _initialIndex = _findInitialIndex();
  PageController? _pageController;
  PageController get _pages => _pageController ??= PageController(
    viewportFraction: 0.86,
    initialPage: _initialIndex,
  );

  /// 밝은 하늘을 입힌 지도 스타일. 지도가 만들어지는 동안 미리 받아 둔다.
  late final Future<String?> _style = _lightSkyStyle();
  bool _customStyle = false;
  bool _pinsAdded = false;

  MapboxMap? _map;
  CircleAnnotationManager? _dotLayer;
  PointAnnotationManager? _cardLayer;
  Cancelable? _tapSubscription;

  /// 지도에 올린 카드와 점. 장소를 지울 때 함께 지운다.
  final Map<String, _Pin> _pinByAnnotation = {};
  final Map<_Pin, PointAnnotation> _cardOf = {};
  final Map<_Pin, CircleAnnotation> _dotOf = {};
  late int _current = _initialIndex;

  int _findInitialIndex() {
    final targetPlace = widget.initialPlace;
    final targetCode = widget.initialLink?.code;
    if (targetPlace != null) {
      final index = _pins.indexWhere(
        (pin) =>
            (targetCode == null || pin.link.code == targetCode) &&
            identical(pin.place, targetPlace),
      );
      if (index >= 0) return index;
      final byValue = _pins.indexWhere(
        (pin) =>
            (targetCode == null || pin.link.code == targetCode) &&
            pin.place.name == targetPlace.name &&
            pin.place.lat == targetPlace.lat &&
            pin.place.lng == targetPlace.lng,
      );
      if (byValue >= 0) return byValue;
    }
    if (targetCode != null) {
      final index = _pins.indexWhere((pin) => pin.link.code == targetCode);
      if (index >= 0) return index;
    }
    return 0;
  }

  @override
  void dispose() {
    _tapSubscription?.cancel();
    _cards.close();
    _pageController?.dispose();
    super.dispose();
  }

  /// Outdoors 스타일은 멀리서 볼 때 지구본 밖 우주가 검은색이고 별이 뜬다.
  /// Flutter SDK 에는 하늘(fog)을 바꾸는 API 가 없어서, 스타일 JSON 을 받아 하늘만
  /// 밝은 하늘색으로 바꿔 쓴다. 받지 못하면 원래 스타일 그대로 둔다.
  static Future<String?> _lightSkyStyle() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12'
              '?access_token=${AppConfig.mapboxToken}',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final style =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      style['fog'] = _lightSky;
      style['name'] = _styleName;
      return jsonEncode(style);
    } on Exception {
      return null;
    }
  }

  /// 바꾼 스타일에 붙이는 이름. 스타일이 다 읽혔을 때 어느 스타일인지 가린다.
  static const _styleName = 'townloader-light-sky';

  static const Map<String, Object> _lightSky = {
    'range': [1, 20],
    // 지평선 근처의 옅은 안개와 그 위 하늘.
    'color': 'hsl(195, 70%, 96%)',
    'high-color': 'hsl(200, 80%, 84%)',
    'horizon-blend': 0.08,
    // 지구본 밖. 레퍼런스처럼 연한 하늘색으로 두고 별은 끈다.
    'space-color': 'hsl(198, 65%, 90%)',
    'star-intensity': 0,
  };

  /// 스타일이 다 읽힌 뒤에 점과 카드를 올린다.
  ///
  /// 지도는 처음에 기본 스타일을 읽고, 곧바로 밝은 하늘 스타일로 갈아끼운다. 기본
  /// 스타일이 늦게 다 읽히면 그 위에 올린 점이 갈아끼울 때 사라지므로, 밝은 하늘
  /// 스타일이 읽혔을 때만 올린다.
  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (!_customStyle || map == null) return;
    final json = await map.getStyleJSON();
    if (json.contains(_styleName)) await _addPins();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    // 처음에는 멀리서 지구본을 보여 주고, 장소들 쪽으로 날아간다.
    final first = _pins.isEmpty ? null : _pins[_current].point;
    await map.setCamera(
      CameraOptions(
        center: first ?? Point(coordinates: Position(127.5, 36.5)),
        zoom: 1.2,
      ),
    );
    final style = await _style;
    if (!mounted) return;
    if (style != null) {
      _customStyle = true;
      await map.setStyleJSON(style);
    } else {
      await _addPins();
    }
  }

  Future<void> _addPins() async {
    final map = _map;
    if (map == null || _pinsAdded || !mounted) return;
    _pinsAdded = true;
    await map.setProjection(StyleProjection(name: StyleProjectionName.globe));
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    if (_pins.isEmpty) return;

    // 점은 늘 보이고, 카드는 겹치지 않는 것만 보인다.
    final dots = await map.annotations.createCircleAnnotationManager();
    _dotLayer = dots;
    final created = await dots.createMulti([
      for (final pin in _pins) _dotOptions(pin),
    ]);
    for (final (index, dot) in created.indexed) {
      if (dot != null && index < _pins.length) _dotOf[_pins[index]] = dot;
    }
    final cards = await map.annotations.createPointAnnotationManager();
    await cards.setIconAllowOverlap(false);
    await cards.setIconIgnorePlacement(false);
    _cardLayer = cards;
    _tapSubscription = cards.tapEvents(
      onTap: (annotation) {
        final pin = _pinByAnnotation[annotation.id];
        final index = pin == null ? -1 : _pins.indexOf(pin);
        if (index >= 0) _select(index, fromMap: true);
      },
    );

    await _flyToInitial();
    await _addCards();
  }

  CircleAnnotationOptions _dotOptions(_Pin pin) => CircleAnnotationOptions(
    geometry: pin.point,
    circleRadius: 5.5,
    circleColor: _colorOf(pin.link),
    circleStrokeWidth: 2,
    circleStrokeColor: 0xFFFFFFFF,
  );

  Future<void> _flyToInitial() {
    if (widget.initialPlace != null) {
      return _fitPoints([_pins[_current].point]);
    }
    final code = widget.initialLink?.code;
    if (code != null) {
      final linkPoints = [
        for (final pin in _pins)
          if (pin.link.code == code) pin.point,
      ];
      if (linkPoints.isNotEmpty) return _fitPoints(linkPoints);
    }
    return _fitAll();
  }

  /// 모든 장소(또는 [category] 의 장소)가 한 화면에 들어오게. 나라를 넘나들면 지구본이
  /// 보일 만큼 멀리서 본다.
  Future<void> _fitAll([SavedLink? link]) => _fitPoints([
    for (final pin in _pins)
      if (link == null || pin.link.code == link.code) pin.point,
  ]);

  Future<void> _fitPoints(List<Point> points) async {
    final map = _map;
    if (map == null || points.isEmpty) return;
    final size = MediaQuery.sizeOf(context);
    final camera = await map.cameraForCoordinatesPadding(
      points,
      CameraOptions(),
      MbxEdgeInsets(top: 190, left: 48, bottom: 220, right: 48),
      points.length == 1 ? 13 : 14,
      null,
    );
    await map.flyTo(
      CameraOptions(
        center: camera.center,
        zoom: math.min(camera.zoom ?? 2, size.width < 500 ? 14 : 15),
      ),
      MapAnimationOptions(duration: 1600),
    );
  }

  /// 카드는 그림을 만드는 데 시간이 걸려서, 만들어지는 대로 하나씩 올린다.
  /// 눌러서 들어온 글의 장소를 먼저 그리고, 겹칠 때도 이기도록 정렬 키를 앞세운다.
  Future<void> _addCards() async {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final focusCode = widget.initialLink?.code;
    final order = [
      if (widget.initialPlace != null && _pins.isNotEmpty) _current,
      for (final (index, pin) in _pins.indexed)
        if (index != _current && focusCode != null && pin.link.code == focusCode)
          index,
      for (final (index, pin) in _pins.indexed)
        if ( !(widget.initialPlace != null && index == _current) &&
            !(focusCode != null && pin.link.code == focusCode))
          index,
    ];
    final pins = [for (final index in order) _pins[index]];
    for (final (rank, pin) in pins.indexed) {
      await _addCard(pin, rank.toDouble(), pixelRatio);
      if (!mounted) return;
    }
  }

  Future<void> _addCard(_Pin pin, double sortKey, double pixelRatio) async {
    final image = await _cards.render(
      title: pin.place.name,
      subtitle: pin.link.author == null ? '' : '@${pin.link.author}',
      photoUrl: pin.link.photoFor(pin.place),
      pixelRatio: pixelRatio,
    );
    final layer = _cardLayer;
    // 카드를 그리는 사이에 지운 장소면 올리지 않는다.
    if (!mounted || layer == null || !_pins.contains(pin)) return;
    final annotation = await layer.create(
      PointAnnotationOptions(
        geometry: pin.point,
        image: image,
        iconAnchor: IconAnchor.BOTTOM,
        iconOffset: [0, -4],
        symbolSortKey: sortKey,
      ),
    );
    _pinByAnnotation[annotation.id] = pin;
    _cardOf[pin] = annotation;
  }

  /// 길게 눌렀을 때. 지울지 한 번 묻는다.
  Future<void> _confirmDelete(_Pin pin) async {
    final s = S.of(context);
    final delete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(pin.place.name),
              subtitle: Text(s.mapDeleteHint),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                s.mapDeletePlace,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (delete == true) await _delete(pin);
  }

  /// 장소를 목록과 지도에서 지우고 저장한다. 잠시 되돌릴 수 있다.
  Future<void> _delete(_Pin pin) async {
    final index = _pins.indexOf(pin);
    if (index < 0) return;
    final s = S.of(context);
    final links = context.read<LinksController>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _pins.removeAt(index);
      if (_current > index || _current >= _pins.length) {
        _current = math.max(0, _current - 1);
      }
    });
    _removeFromMap(pin);
    final at = await links.removePlace(pin.link.code, pin.place);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s.mapPlaceDeleted),
          behavior: SnackBarBehavior.floating,
          action: at < 0
              ? null
              : SnackBarAction(
                  label: s.undo,
                  onPressed: () => _restore(links, pin, index, at),
                ),
        ),
      );
  }

  /// 되돌리기는 지도를 닫은 뒤에 눌러도 저장은 되돌린다.
  Future<void> _restore(
    LinksController links,
    _Pin pin,
    int index,
    int placeIndex,
  ) async {
    await links.insertPlace(
      pin.link.code,
      pin.place,
      placeIndex,
    );
    if (!mounted) return;
    setState(() => _pins.insert(index.clamp(0, _pins.length), pin));
    final dot = await _dotLayer?.create(_dotOptions(pin));
    if (dot != null) _dotOf[pin] = dot;
    if (!mounted) return;
    await _addCard(pin, 0, MediaQuery.devicePixelRatioOf(context));
  }

  void _removeFromMap(_Pin pin) {
    final card = _cardOf.remove(pin);
    if (card != null) {
      _pinByAnnotation.remove(card.id);
      _cardLayer?.delete(card);
    }
    final dot = _dotOf.remove(pin);
    if (dot != null) _dotLayer?.delete(dot);
  }

  void _select(int index, {bool fromMap = false}) {
    setState(() => _current = index);
    if (fromMap && _pages.hasClients) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _map?.flyTo(
      CameraOptions(center: _pins[index].point, zoom: 13.5),
      MapAnimationOptions(duration: 1200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);

    if (!AppConfig.hasMapbox) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title ?? widget.category ?? s.mapAll)),
        body: MessageView(icon: Icons.public_off, title: s.mapUnavailable),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            styleUri: MapboxStyles.OUTDOORS,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Material(
                          color: theme.colorScheme.surface,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Text(
                              '${widget.title ?? widget.category ?? s.mapAll} · ${s.linksPlaceCount(_pins.length)}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_pins.length > 1)
                        IconButton.filledTonal(
                          tooltip: s.mapShowAll,
                          onPressed: _fitAll,
                          icon: const Icon(Icons.public),
                        ),
                    ],
                  ),
                ),
                // 범례: 글마다 색과 장소 수. 누르면 그 글의 장소로 날아간다.
                if (_legendLinks.length > 1)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      children: [
                        for (final link in _legendLinks) ...[
                          _LegendChip(
                            label: _nameOf(link),
                            count: _pins
                                .where((pin) => pin.link.code == link.code)
                                .length,
                            color: Color(_colorOf(link)),
                            onTap: () => _fitAll(link),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_pins.isEmpty)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(s.mapNoPlaces),
                ),
              ),
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 112,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _pins.length,
                    onPageChanged: (index) {
                      if (index != _current) _select(index);
                    },
                    itemBuilder: (context, index) {
                      final pin = _pins[index];
                      final tile = _PlaceTile(
                        pin: pin,
                        color: Color(_colorOf(pin.link)),
                        selected: index == _current,
                        onTap: () => _select(index),
                        onLongPress: _editable
                            ? () => _confirmDelete(pin)
                            : null,
                      );
                      if (!_editable) return tile;
                      // 위로 밀면 바로 지운다. 옆으로 넘기는 것과 겹치지 않는다.
                      return Dismissible(
                        key: ObjectKey(pin),
                        direction: DismissDirection.up,
                        onDismissed: (_) => _delete(pin),
                        child: tile,
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.pin,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final _Pin pin;

  /// 이 장소가 속한 카테고리의 점 색.
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// 내 지도에서만 있다. 길게 누르면 지울지 묻는다.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final place = pin.place;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: selected ? 6 : 2,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Row(
            children: [
              SizedBox(
                width: 100,
                height: double.infinity,
                child: NetworkThumb(url: pin.link.photoFor(place)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (place.address != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          place.approximate
                              ? '${place.address} · ${s.linksApproximate}'
                              : place.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              [
                                if (pin.link.title != null) pin.link.title!,
                                if (pin.link.author != null)
                                  '@${pin.link.author}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text('$label $count', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}
