import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/hiker_client.dart';
import 'data/ig_repository.dart';
import 'data/threads_client.dart';
import 'services/download_service.dart';
import 'services/file_saver.dart';
import 'services/settings_store.dart';
import 'state/profile_controller.dart';
import 'state/resolve_controller.dart';
import 'state/settings_controller.dart';
import 'ui/root_shell.dart';
import 'ui/theme.dart';

/// 의존성을 조립하고 최상위 화면을 띄운다.
class TownloaderApp extends StatefulWidget {
  const TownloaderApp({super.key});

  @override
  State<TownloaderApp> createState() => _TownloaderAppState();
}

class _TownloaderAppState extends State<TownloaderApp> {
  late final SettingsStore _store = SettingsStore();
  late final SettingsController _settings = SettingsController(_store);

  /// 클라이언트는 키를 직접 들고 있지 않고 매 호출마다 컨트롤러에서 읽어간다.
  /// 덕분에 설정에서 키를 바꿔도 재조립이 필요 없다.
  late final HikerClient _client = HikerClient(
    readApiKey: () => _settings.apiKey,
  );
  late final ThreadsClient _threadsClient = ThreadsClient();
  late final IgRepository _repository = IgRepository(
    _client,
    threadsClient: _threadsClient,
  );
  late final DownloadService _downloads = DownloadService(settings: _store);

  @override
  void initState() {
    super.initState();
    _settings.load();
    MediaFileSaver.clearShareCache();
  }

  @override
  void dispose() {
    _downloads.dispose();
    _threadsClient.close();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _downloads),
        ChangeNotifierProvider(create: (_) => ResolveController(_repository)),
        ChangeNotifierProvider(create: (_) => ProfileController(_repository)),
      ],
      child: MaterialApp(
        title: 'Townloader',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ko'),
          Locale('en'),
        ],
        home: const RootShell(),
      ),
    );
  }
}
