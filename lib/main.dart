import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app.dart';
import 'config/app_config.dart';

void main() {
  if (AppConfig.hasMapbox) MapboxOptions.setAccessToken(AppConfig.mapboxToken);
  runApp(const TownloaderApp());
}
