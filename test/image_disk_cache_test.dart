import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:townloader/services/image_disk_cache.dart';

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationCachePath() async => path;
}

void main() {
  test('새로 받는 이미지는 받자마자 파일을 돌려준다', () async {
    final dir = await Directory.systemTemp.createTemp('image_cache_test');
    addTearDown(() => dir.delete(recursive: true));
    PathProviderPlatform.instance = _TempPathProvider(dir.path);
    HttpOverrides.global = null;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..add([1, 2, 3])
        ..close();
    });

    final file = await ImageDiskCache.instance
        .fileFor('http://127.0.0.1:${server.port}/new.jpg')
        .timeout(const Duration(seconds: 5));
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
}
