import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';
import '../models/ig_asset.dart';
import '../models/ig_post.dart';
import 'file_saver.dart';
import 'settings_store.dart';

enum DownloadStatus { queued, running, completed, failed, canceled }

extension DownloadStatusLabel on DownloadStatus {
  String get label => switch (this) {
    DownloadStatus.queued => '대기 중',
    DownloadStatus.running => '받는 중',
    DownloadStatus.completed => '완료',
    DownloadStatus.failed => '실패',
    DownloadStatus.canceled => '취소됨',
  };

  bool get isFinished =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.canceled;
}

/// 다운로드 목록에 표시되는 항목 하나. 파일 하나에 대응한다.
class DownloadItem {
  DownloadItem({
    required this.id,
    required this.title,
    required this.filename,
    required this.asset,
    required this.subfolder,
    this.thumbnailUrl,
  });

  final String id;

  /// 목록에 보여줄 제목. 보통 `@계정 · 릴스` 형태.
  final String title;
  final String filename;
  final IgAsset asset;

  /// 데스크톱에서 파일을 넣을 하위 폴더 이름(보통 계정명).
  final String subfolder;
  final String? thumbnailUrl;

  DownloadStatus status = DownloadStatus.queued;
  int receivedBytes = 0;
  int? totalBytes;
  SavedLocation? savedLocation;
  String? errorMessage;

  /// 총 크기를 모르면 null(불확정 진행 표시).
  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.running;
}

/// 다운로드 큐. 동시에 [_maxConcurrent] 개까지만 실제로 내려받는다.
class DownloadService extends ChangeNotifier {
  DownloadService({
    required SettingsStore settings,
    http.Client? httpClient,
    MediaFileSaver saver = const MediaFileSaver(),
  }) : _settings = settings,
       _http = httpClient ?? http.Client(),
       _saver = saver;

  static const int _maxConcurrent = 3;

  final SettingsStore _settings;
  final http.Client _http;
  final MediaFileSaver _saver;

  final List<DownloadItem> _items = [];
  final Map<String, StreamSubscription<List<int>>> _running = {};

  /// 최근 항목이 위로 오도록 뒤집어서 노출한다.
  List<DownloadItem> get items => List.unmodifiable(_items.reversed);

  int get activeCount => _items.where((item) => item.isActive).length;

  int get completedCount =>
      _items.where((item) => item.status == DownloadStatus.completed).length;

  /// 게시물 하나를 큐에 넣는다. 캐러셀이면 슬라이드마다 항목이 하나씩 생긴다.
  /// 실제로 큐에 들어간 파일 수를 돌려준다.
  int enqueuePost(IgPost post, {required QualityPreference quality}) {
    var added = 0;
    for (var index = 0; index < post.items.length; index++) {
      final item = post.items[index];
      final asset = quality == QualityPreference.best
          ? item.best
          : item.smallest;
      if (asset == null) continue;

      _items.add(
        DownloadItem(
          id: '${post.pk}-${item.id}-${DateTime.now().microsecondsSinceEpoch}',
          title:
              '@${post.authorName} · ${post.kind.localizedLabel(S.current.isKo)}',
          filename: buildFilename(
            post,
            asset,
            index: index,
            total: post.items.length,
          ),
          asset: asset,
          subfolder: post.authorName,
          thumbnailUrl: item.thumbnailUrl,
        ),
      );
      added++;
    }

    if (added > 0) {
      notifyListeners();
      unawaited(_pump());
    }
    return added;
  }

  /// 사용자가 화질을 직접 고른 경우, 그 변형 하나만 큐에 넣는다.
  void enqueueAsset(
    IgPost post,
    IgAsset asset, {
    required int index,
    required String? thumbnailUrl,
  }) {
    _items.add(
      DownloadItem(
        id: '${post.pk}-$index-${DateTime.now().microsecondsSinceEpoch}',
        title:
            '@${post.authorName} · ${post.kind.localizedLabel(S.current.isKo)}',
        filename: buildFilename(
          post,
          asset,
          index: index,
          total: post.items.length,
        ),
        asset: asset,
        subfolder: post.authorName,
        thumbnailUrl: thumbnailUrl,
      ),
    );
    notifyListeners();
    unawaited(_pump());
  }

  int enqueueAll(Iterable<IgPost> posts, {required QualityPreference quality}) {
    var added = 0;
    for (final post in posts) {
      added += enqueuePost(post, quality: quality);
    }
    return added;
  }

  /// `nasa_DcMXl1IPNtB.mp4` 또는 캐러셀이면 `nasa_DcmROZxILwv_2.jpg`.
  @visibleForTesting
  static String buildFilename(
    IgPost post,
    IgAsset asset, {
    required int index,
    required int total,
  }) {
    final author = _sanitize(post.authorName);
    final identifier = _sanitize(post.code ?? post.pk);
    final suffix = total > 1 ? '_${index + 1}' : '';
    return '${author}_$identifier$suffix.${asset.fileExtension}';
  }

  /// 파일명에 쓸 수 없는 문자를 밑줄로 바꾼다.
  static String _sanitize(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'instagram' : cleaned;
  }

  void cancel(String id) {
    final item = _items.firstWhereOrNull((entry) => entry.id == id);
    if (item == null || item.status.isFinished) return;

    _running.remove(id)?.cancel();
    item.status = DownloadStatus.canceled;
    notifyListeners();
    unawaited(_pump());
  }

  void retry(String id) {
    final item = _items.firstWhereOrNull((entry) => entry.id == id);
    if (item == null || item.isActive) return;

    item
      ..status = DownloadStatus.queued
      ..receivedBytes = 0
      ..totalBytes = null
      ..errorMessage = null
      ..savedLocation = null;
    notifyListeners();
    unawaited(_pump());
  }

  /// 끝난 항목만 목록에서 지운다. 진행 중인 것은 남긴다.
  void clearFinished() {
    for (final item in _items.where((item) => item.status.isFinished)) {
      // 목록에서 빠지면 공유 버튼도 사라지므로 캐시에 남긴 사본을 함께 지운다.
      final location = item.savedLocation;
      if (location != null && location.sharesCachedCopy) {
        unawaited(_deleteQuietly(File(location.sharePath!)));
      }
    }
    _items.removeWhere((item) => item.status.isFinished);
    notifyListeners();
  }

  /// 빈 자리가 있으면 대기 중인 항목을 시작시킨다.
  Future<void> _pump() async {
    while (_running.length < _maxConcurrent) {
      final next = _items.firstWhereOrNull(
        (item) => item.status == DownloadStatus.queued,
      );
      if (next == null) return;

      next.status = DownloadStatus.running;
      notifyListeners();
      unawaited(_run(next));

      // _run 이 구독을 등록할 때까지 기다려야 동시 실행 수가 정확해진다.
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _run(DownloadItem item) async {
    File? tempFile;
    IOSink? sink;

    try {
      final request = http.Request('GET', Uri.parse(item.asset.url));
      // 인스타그램 CDN 은 기본 UA 로도 응답하지만, 일부 엣지에서 차단되는 경우가 있어
      // 일반 브라우저와 같은 헤더를 붙인다.
      request.headers['user-agent'] =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';
      request.headers['accept'] = '*/*';

      final response = await _http.send(request);
      if (response.statusCode != 200) {
        throw HttpException('CDN 응답 오류 (HTTP ${response.statusCode})');
      }

      item.totalBytes = response.contentLength;

      final tempDir = await getTemporaryDirectory();
      // 샌드박스 컨테이너에서는 캐시 폴더가 아직 없을 수 있어 직접 만들어야 한다.
      await tempDir.create(recursive: true);
      tempFile = File(
        '${tempDir.path}/townloader_${DateTime.now().microsecondsSinceEpoch}_${item.filename}',
      );
      sink = tempFile.openWrite();

      final completer = Completer<void>();
      final subscription = response.stream.listen(
        (chunk) {
          sink!.add(chunk);
          item.receivedBytes += chunk.length;
          notifyListeners();
        },
        onDone: () => completer.complete(),
        onError: completer.completeError,
        cancelOnError: true,
      );
      _running[item.id] = subscription;

      try {
        await completer.future;
      } finally {
        _running.remove(item.id);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // 스트림이 도는 사이 사용자가 취소했다면 여기서 정리하고 끝낸다.
      if (item.status == DownloadStatus.canceled) {
        await _deleteQuietly(tempFile);
        return;
      }

      item.savedLocation = await _saver.save(
        tempFile: tempFile,
        filename: item.filename,
        isVideo: item.asset.isVideo,
        subfolder: item.subfolder,
        saveToGallery: await _settings.readSaveToGallery(),
      );
      item.status = DownloadStatus.completed;
    } catch (error) {
      // 취소로 인한 스트림 중단은 실패로 표시하지 않는다.
      if (item.status != DownloadStatus.canceled) {
        item.status = DownloadStatus.failed;
        item.errorMessage = _describe(error);
      }
      await _closeQuietly(sink);
      if (tempFile != null) await _deleteQuietly(tempFile);
    } finally {
      _running.remove(item.id);
      notifyListeners();
      unawaited(_pump());
    }
  }

  static String _describe(Object error) => switch (error) {
    SaveException() => error.message,
    HttpException() => error.message,
    SocketException() => '네트워크 연결이 끊겼습니다.',
    FileSystemException() => '파일을 저장할 수 없습니다: ${error.message}',
    _ => '$error',
  };

  static Future<void> _closeQuietly(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.close();
    } catch (_) {
      // 이미 닫혔거나 쓰기가 실패한 경우로, 여기서 할 수 있는 일이 없다.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 임시 파일이 남더라도 OS 가 정리하므로 무시한다.
    }
  }

  @override
  void dispose() {
    for (final subscription in _running.values) {
      subscription.cancel();
    }
    _running.clear();
    _http.close();
    super.dispose();
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
