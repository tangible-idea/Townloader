import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 네트워크 이미지를 앱 캐시 폴더에 파일로 남겨 두는 디스크 캐시.
///
/// `Image.network` 는 메모리 캐시만 있어서, 목록을 스크롤해 메모리에서 밀려난 이미지를
/// 다시 보면 네트워크로 또 받는다. 여기서는 한 번 받은 이미지를 파일로 두고 재사용한다.
class ImageDiskCache {
  ImageDiskCache._();

  static final instance = ImageDiskCache._();

  /// 폴더가 이 크기를 넘으면 앱을 켤 때 오래된 파일부터 지운다.
  static const _maxBytes = 300 * 1024 * 1024;

  final _client = http.Client();
  final _inFlight = <String, Future<File>>{};
  Future<Directory>? _directory;

  Future<Directory> get _dir => _directory ??= _open();

  Future<Directory> _open() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/images');
    await dir.create(recursive: true);
    unawaited(_prune(dir));
    return dir;
  }

  /// [url] 이미지 파일을 돌려준다. 디스크에 없으면 받아서 저장한다.
  /// [onProgress] 는 실제로 네트워크에서 받을 때만 불린다.
  Future<File> fileFor(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final file = await _fileOf(url);
    if (await file.exists()) return file;
    return _inFlight[url] ??= _download(
      url,
      file,
      onProgress,
    ).whenComplete(() => _inFlight.remove(url));
  }

  /// 디코딩에 실패한 파일(HTML 오류 페이지 등)을 지워 다음에 다시 받게 한다.
  Future<void> evict(String url) async {
    try {
      await (await _fileOf(url)).delete();
    } catch (_) {}
  }

  Future<File> _fileOf(String url) async =>
      File('${(await _dir).path}/${_hash(url)}');

  Future<File> _download(
    String url,
    File file,
    void Function(int received, int? total)? onProgress,
  ) async {
    final uri = Uri.parse(url);
    final response = await _client.send(http.Request('GET', uri));
    if (response.statusCode != HttpStatus.ok) {
      unawaited(response.stream.drain<void>());
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    final temp = File('${file.path}.part');
    final sink = temp.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
      }
      await sink.close();
      if (received == 0) {
        throw NetworkImageLoadException(statusCode: 200, uri: uri);
      }
      return await temp.rename(file.path);
    } catch (_) {
      await sink.close().catchError((_) {});
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _prune(Directory dir) async {
    try {
      final entries = <(File, FileStat)>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        // 받다가 앱이 꺼져 남은 조각 파일.
        if (entity.path.endsWith('.part')) {
          await entity.delete();
          continue;
        }
        final stat = await entity.stat();
        entries.add((entity, stat));
        total += stat.size;
      }
      if (total <= _maxBytes) return;
      entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in entries) {
        if (total <= _maxBytes * 0.8) break;
        await file.delete();
        total -= stat.size;
      }
    } catch (_) {}
  }

  /// URL 을 파일 이름으로 쓰기 위한 FNV-1a 해시.
  static String _hash(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${hash.toRadixString(16)}_${url.length}';
  }
}

/// [ImageDiskCache] 를 거쳐 그리는 이미지.
///
/// [targetWidth]·[targetHeight](물리 픽셀)를 주면 그 상자를 덮을 만큼만 줄여서 디코딩한다.
/// 18px 칩에 원본 해상도 사진을 통째로 올려 메모리 캐시가 금방 차는 것을 막는다.
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, {this.targetWidth, this.targetHeight});

  final String url;
  final int? targetWidth;
  final int? targetHeight;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(decode, chunks),
      chunkEvents: chunks.stream,
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
      ],
    );
  }

  Future<ui.Codec> _load(
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    try {
      final file = await ImageDiskCache.instance.fileFor(
        url,
        onProgress: (received, total) => chunks.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: received,
            expectedTotalBytes: total,
          ),
        ),
      );
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        await file.readAsBytes(),
      );
      try {
        return await decode(buffer, getTargetSize: _targetSize);
      } catch (_) {
        await ImageDiskCache.instance.evict(url);
        rethrow;
      }
    } finally {
      unawaited(chunks.close());
    }
  }

  ui.TargetImageSize _targetSize(int width, int height) {
    final scale = [
      if (targetWidth != null) targetWidth! / width,
      if (targetHeight != null) targetHeight! / height,
    ].fold<double?>(null, (a, b) => a == null || b > a ? b : a);
    if (scale == null || scale >= 1) return const ui.TargetImageSize();
    return ui.TargetImageSize(
      width: (width * scale).ceil(),
      height: (height * scale).ceil(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage &&
      other.url == url &&
      other.targetWidth == targetWidth &&
      other.targetHeight == targetHeight;

  @override
  int get hashCode => Object.hash(url, targetWidth, targetHeight);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DiskCachedImage')}("$url", '
      '${targetWidth}x$targetHeight)';
}
