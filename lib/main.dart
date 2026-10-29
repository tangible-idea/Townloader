import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';

void main() {
  // 토큰은 플랫폼 채널로 넘어가므로 바인딩이 먼저 있어야 한다. 없으면 토큰 설정이
  // 조용히 실패하고, 지도를 열 때 "valid access token" 오류가 난다.
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.hasMapbox) MapboxOptions.setAccessToken(AppConfig.mapboxToken);
  runApp(const TownloaderApp());
}
