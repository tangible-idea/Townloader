import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/saved_link.dart';

/// Links 탭의 카테고리와 저장한 글. 기기 안의 JSON 파일 하나에 담는다.
class LinksData {
  const LinksData({required this.categories, required this.links});

  final List<String> categories;
  final List<SavedLink> links;
}

/// [LinksData] 를 읽고 쓴다. 테스트에서는 메모리에 두는 것으로 바꿔 끼운다.
abstract class LinksStore {
  Future<LinksData?> load();

  Future<void> save(LinksData data);
}

class FileLinksStore implements LinksStore {
  FileLinksStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> get _file async =>
      File('${(await _directory()).path}/links.json');

  @override
  Future<LinksData?> load() async {
    final file = await _file;
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LinksData(
        categories: [
          for (final name in json['categories'] as List? ?? const [])
            if (name is String) name,
        ],
        links: [
          for (final link in json['links'] as List? ?? const [])
            if (link is Map<String, dynamic>) SavedLink.fromJson(link),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(LinksData data) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    // 쓰다가 꺼져도 이전 내용이 남도록 임시 파일에 쓴 뒤 바꿔 끼운다.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'categories': data.categories,
        'links': [for (final link in data.links) link.toJson()],
      }),
    );
    await temp.rename(file.path);
  }
}

class MemoryLinksStore implements LinksStore {
  MemoryLinksStore([this.data]);

  LinksData? data;

  @override
  Future<LinksData?> load() async => data;

  @override
  Future<void> save(LinksData data) async => this.data = data;
}
