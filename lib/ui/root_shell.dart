import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/maps_client.dart';
import '../l10n/strings.dart';
import '../services/share_intake.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'links_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'shared_map_screen.dart';

/// 화면 폭에 따라 하단 탭 / 사이드 레일로 바뀌는 최상위 뼈대.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  static const int _linksIndex = 0;
  static const int _homeIndex = 1;
  static const int _profileIndex = 2;

  int _index = _linksIndex;

  /// 홈에서 프로필 링크를 만났을 때 프로필 화면을 직접 열기 위해 필요하다.
  final _profileKey = GlobalKey<ProfileScreenState>();

  /// 링크 탭이 받지 않는 공유 링크를 읽기 화면에 넘기기 위해 필요하다.
  final _homeKey = GlobalKey<HomeScreenState>();

  /// 공유 시트로 들어온 링크를 링크 탭에 바로 저장하기 위해 필요하다.
  final _linksKey = GlobalKey<LinksScreenState>();

  final _shareIntake = ShareIntake();
  StreamSubscription<String>? _shareSubscription;

  /// 지도 공유 링크(Universal Link · App Link). 앱이 꺼져 있다 열린 경우도 처음에 한 번 온다.
  StreamSubscription<Uri>? _deepLinkSubscription;

  @override
  void initState() {
    super.initState();
    _shareSubscription = _shareIntake.links.listen(_openSharedLink);
    _shareIntake.start();
    _deepLinkSubscription = AppLinks().uriLinkStream.listen(
      _openDeepLink,
      // 딥링크 플러그인이 없는 플랫폼(테스트·데스크톱).
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    _shareSubscription?.cancel();
    _shareIntake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final destinations = <_Destination>[
      // 다운로드 목록은 Links 탭 오른쪽 위 아이콘으로 옮겼다.
      _Destination(
        icon: Icons.bookmarks_outlined,
        selectedIcon: Icons.bookmarks,
        label: s.navLinks,
      ),
      _Destination(
        icon: Icons.chrome_reader_mode_outlined,
        selectedIcon: Icons.chrome_reader_mode,
        label: s.navDownload,
      ),
      _Destination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: s.navProfile,
      ),
      _Destination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: s.navSettings,
      ),
    ];

    final pages = IndexedStack(
      index: _index,
      children: [
        LinksScreen(key: _linksKey, onOpenRead: _openRead),
        HomeScreen(
          key: _homeKey,
          onOpenProfile: _openProfile,
          onOpenDownloads: _openDownloads,
        ),
        ProfileScreen(key: _profileKey, onOpenDownloads: _openDownloads),
        const SettingsScreen(),
      ],
    );

    // 넓은 화면(데스크톱·태블릿)에서는 세로 레일이 더 편하다.
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: destination.buildIcon(context, selected: false),
                    selectedIcon: destination.buildIcon(
                      context,
                      selected: true,
                    ),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: destination.buildIcon(context, selected: false),
              selectedIcon: destination.buildIcon(context, selected: true),
              label: destination.label,
            ),
        ],
      ),
    );
  }

  /// 공유한 링크는 링크 탭에 저장한다. 링크 탭이 받지 않는 링크(Threads, 프로필 등)는
  /// 읽기 화면에서 연다.
  void _openSharedLink(String link) {
    setState(() => _index = _linksIndex);
    // 앱이 공유로 막 켜졌다면 각 화면 state 가 첫 프레임 뒤에 준비된다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await _linksKey.currentState?.handleSharedLink(link);
      if (saved != false || !mounted) return;
      setState(() => _index = _homeIndex);
      _homeKey.currentState?.handleSharedLink(link);
    });
  }

  void _openDeepLink(Uri uri) {
    final id = context.read<MapsClient>().shareIdOf(uri);
    if (id == null || !mounted) return;
    SharedMapScreen.open(context, id);
  }

  void _openDownloads() => DownloadsScreen.open(context);

  void _openRead(String link) {
    setState(() => _index = _homeIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeKey.currentState?.handleSharedLink(link);
    });
  }

  void _openProfile(String username) {
    setState(() => _index = _profileIndex);
    // 프로필 화면이 IndexedStack 안에 이미 만들어져 있으므로 바로 호출해도 되지만,
    // 첫 진입이라면 프레임이 지난 뒤에 state 가 준비된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _profileKey.currentState?.openUsername(username);
    });
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  Widget buildIcon(BuildContext context, {required bool selected}) =>
      Icon(selected ? selectedIcon : icon);
}
