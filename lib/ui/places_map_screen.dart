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
class PlacesMapScreen extends StatefulWidget {
  const PlacesMapScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PlacesMapScreen()));

  /// 카테고리 점 색. Links 탭의 카테고리 순서대로 돌려 쓴다. 밝은 지도 위에서 서로
  /// 구분되도록 고른 색이다.
  static const List<int> categoryColors = [
    0xFF0B7A5E, // 초록
    0xFFE8590C, // 주황
    0xFF1C7ED6, // 파랑
    0xFFD6336C, // 분홍
    0xFF7048E8, // 보라
    0xFFF08C00, // 노랑
    0xFF0C8599, // 청록
    0xFF5C3B1E, // 갈색
  ];

  static int colorOf(List<String> categories, String category) {
    final index = categories.indexOf(category);
    return categoryColors[(index < 0 ? 0 : index) % categoryColors.length];
  }

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
  late final List<String> _allCategories = context
      .read<LinksController>()
      .categories;
  late final List<_Pin> _pins = [
    for (final link in context.read<LinksController>().allLinks)
      for (final place in link.places) _Pin(place, link),
  ];

  /// 장소가 하나라도 있는 카테고리. 범례에 보인다.
  late final List<String> _categories = [
    for (final category in _allCategories)
      if (_pins.any((pin) => pin.link.category == category)) category,
  ];

  int _colorOf(String category) =>
      PlacesMapScreen.colorOf(_allCategories, category);
  final _cards = PlaceCardImage();
  final _pages = PageController(viewportFraction: 0.86);

  /// 밝은 하늘을 입힌 지도 스타일. 지도가 만들어지는 동안 미리 받아 둔다.
  late final Future<String?> _style = _lightSkyStyle();
  bool _customStyle = false;
  bool _pinsAdded = false;

  MapboxMap? _map;
  PointAnnotationManager? _cardLayer;
  Cancelable? _tapSubscription;
  final Map<String, int> _pinByAnnotation = {};
  int _current = 0;

  @override
  void dispose() {
    _tapSubscription?.cancel();
    _cards.close();
    _pages.dispose();
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
    final first = _pins.isEmpty ? null : _pins.first.point;
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
    await dots.createMulti([
      for (final pin in _pins)
        CircleAnnotationOptions(
          geometry: pin.point,
          circleRadius: 5.5,
          circleColor: _colorOf(pin.link.category),
          circleStrokeWidth: 2,
          circleStrokeColor: 0xFFFFFFFF,
        ),
    ]);
    final cards = await map.annotations.createPointAnnotationManager();
    await cards.setIconAllowOverlap(false);
    await cards.setIconIgnorePlacement(false);
    _cardLayer = cards;
    _tapSubscription = cards.tapEvents(
      onTap: (annotation) {
        final index = _pinByAnnotation[annotation.id];
        if (index != null) _select(index, fromMap: true);
      },
    );

    await _fitAll();
    await _addCards();
  }

  /// 모든 장소(또는 [category] 의 장소)가 한 화면에 들어오게. 나라를 넘나들면 지구본이
  /// 보일 만큼 멀리서 본다.
  Future<void> _fitAll([String? category]) async {
    final map = _map;
    if (map == null) return;
    final size = MediaQuery.sizeOf(context);
    final points = [
      for (final pin in _pins)
        if (category == null || pin.link.category == category) pin.point,
    ];
    if (points.isEmpty) return;
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
  /// 먼저 저장한 글의 장소가 겹칠 때 이기도록 순서를 정렬 키로 쓴다.
  Future<void> _addCards() async {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    for (final (index, pin) in _pins.indexed) {
      final image = await _cards.render(
        title: pin.place.name,
        subtitle: pin.link.author == null ? '' : '@${pin.link.author}',
        photoUrl: pin.link.photoFor(pin.place),
        pixelRatio: pixelRatio,
      );
      final layer = _cardLayer;
      if (!mounted || layer == null) return;
      final annotation = await layer.create(
        PointAnnotationOptions(
          geometry: pin.point,
          image: image,
          iconAnchor: IconAnchor.BOTTOM,
          iconOffset: [0, -4],
          symbolSortKey: index.toDouble(),
        ),
      );
      _pinByAnnotation[annotation.id] = index;
    }
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
        appBar: AppBar(title: Text(s.mapAll)),
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
                              '${s.mapAll} · ${s.linksPlaceCount(_pins.length)}',
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
                // 범례: 카테고리 색과 장소 수. 누르면 그 카테고리 장소로 날아간다.
                if (_categories.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      children: [
                        for (final category in _categories) ...[
                          _LegendChip(
                            label: category,
                            count: _pins
                                .where((pin) => pin.link.category == category)
                                .length,
                            color: Color(_colorOf(category)),
                            onTap: () => _fitAll(category),
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
                    itemBuilder: (context, index) => _PlaceTile(
                      pin: _pins[index],
                      color: Color(_colorOf(_pins[index].link.category)),
                      selected: index == _current,
                      onTap: () => _select(index),
                    ),
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
  });

  final _Pin pin;

  /// 이 장소가 속한 카테고리의 점 색.
  final Color color;
  final bool selected;
  final VoidCallback onTap;

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
                                pin.link.category,
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
