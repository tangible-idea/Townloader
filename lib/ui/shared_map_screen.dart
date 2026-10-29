import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/maps_client.dart';
import '../l10n/strings.dart';
import 'places_map_screen.dart';
import 'widgets/state_views.dart';

/// 공유 링크(`<mapsUrl>/m/<id>`)로 들어온 지도. 받아 온 장소를 지도 화면에 그대로 그린다.
class SharedMapScreen extends StatefulWidget {
  const SharedMapScreen({super.key, required this.id});

  final String id;

  static Future<void> open(BuildContext context, String id) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => SharedMapScreen(id: id)));

  @override
  State<SharedMapScreen> createState() => _SharedMapScreenState();
}

class _SharedMapScreenState extends State<SharedMapScreen> {
  late Future<PublicMap> _map = _load();

  Future<PublicMap> _load() => context.read<MapsClient>().publicMap(widget.id);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return FutureBuilder<PublicMap>(
      future: _map,
      builder: (context, snapshot) {
        final map = snapshot.data;
        if (map != null) {
          return PlacesMapScreen(
            links: map.links,
            category: map.category,
            title: map.category,
          );
        }
        return Scaffold(
          appBar: AppBar(),
          body:
              snapshot.hasError
                  ? MessageView(
                    icon: Icons.map_outlined,
                    title:
                        snapshot.error is MapsException
                            ? (snapshot.error as MapsException).message
                            : snapshot.error.toString(),
                    actionLabel: s.retry,
                    onAction: () => setState(() => _map = _load()),
                    isError: true,
                  )
                  : LoadingView(label: s.sharedMapLoading),
        );
      },
    );
  }
}
