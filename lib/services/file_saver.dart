import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';

/// 파일이 최종적으로 어디에 저장되었는지.
class SavedLocation {
  const SavedLocation({
    required this.description,
    this.filePath,
    String? sharePath,
  }) : sharePath = sharePath ?? filePath;

  /// 사용자에게 보여줄 위치 설명.
  final String description;

  /// 디스크 경로. 사진 앨범에만 넣은 경우 null 이다.
  final String? filePath;

  /// 공유 시트·AirDrop 에 넘길 파일. 보통 [filePath] 와 같고, 사진 앨범에 넣은
  /// 경우에는 공유용으로 캐시에 남겨 둔 사본이다. 캐시는 OS 가 비울 수 있다.
  final String? sharePath;

  /// [sharePath] 가 사용자 파일이 아니라 지워도 되는 캐시 사본인지.
  bool get sharesCachedCopy => sharePath != null && sharePath != filePath;
}

class SaveException implements Exception {
  SaveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 내려받은 임시 파일을 플랫폼에 맞는 최종 위치로 옮긴다.
///
/// 데스크톱은 `~/Downloads/Townloader/<계정>/` 아래에 파일을 두고,
/// 모바일은 사진 앱의 Townloader 앨범에 넣는다. 모바일에서 앨범 저장을 끄면
/// 앱 문서 폴더에만 남는다.
class MediaFileSaver {
  const MediaFileSaver();

  static const String albumName = 'Townloader';

  /// 데스크톱(파일 시스템이 사용자에게 그대로 보이는 플랫폼)인지.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<SavedLocation> save({
    required File tempFile,
    required String filename,
    required bool isVideo,
    required String subfolder,
    required bool saveToGallery,
  }) async {
    if (isDesktop) return _saveToDisk(tempFile, filename, subfolder);
    return _saveOnMobile(tempFile, filename, isVideo, saveToGallery);
  }

  Future<SavedLocation> _saveToDisk(
    File tempFile,
    String filename,
    String subfolder,
  ) async {
    // 샌드박스에서 Downloads 접근이 막히면 앱 문서 폴더로 물러선다.
    final base =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final targetDir = Directory('${base.path}/$albumName/$subfolder');
    await targetDir.create(recursive: true);

    final target = _uniquePath(targetDir.path, filename);
    try {
      await tempFile.rename(target.path);
    } on FileSystemException {
      // 임시 폴더와 대상이 서로 다른 볼륨이면 rename 이 실패하므로 복사한다.
      await tempFile.copy(target.path);
      await tempFile.delete();
    }
    return SavedLocation(description: target.path, filePath: target.path);
  }

  Future<SavedLocation> _saveOnMobile(
    File tempFile,
    String filename,
    bool isVideo,
    bool saveToGallery,
  ) async {
    // 앨범 저장을 끄면 앱 문서 폴더에만 남긴다. 파일 앱에서 꺼내 쓸 수 있다.
    if (!saveToGallery) {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/$albumName',
      );
      await dir.create(recursive: true);
      final target = _uniquePath(dir.path, filename);
      await tempFile.rename(target.path);
      return SavedLocation(
        description: S.current.appDocuments,
        filePath: target.path,
      );
    }

    if (!await Gal.hasAccess(toAlbum: true)) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw SaveException('사진 접근 권한이 없어 저장하지 못했습니다. 설정에서 권한을 허용해 주세요.');
      }
    }

    try {
      if (isVideo) {
        await Gal.putVideo(tempFile.path, album: albumName);
      } else {
        await Gal.putImage(tempFile.path, album: albumName);
      }
    } on GalException catch (error) {
      if (await tempFile.exists()) await tempFile.delete();
      throw SaveException('사진 앱에 저장하지 못했습니다: ${error.type.message}');
    }

    // 사진 앱에 들어간 파일은 경로로 다시 꺼낼 수 없으므로, 공유·AirDrop 용으로
    // 임시 파일을 지우지 않고 캐시에 남겨 둔다.
    final shareCopy = await _keepForSharing(tempFile, filename);
    return SavedLocation(
      description: S.current.savedToAlbum(albumName),
      sharePath: shareCopy?.path,
    );
  }

  static const String _shareCacheName = 'townloader_share';

  /// 받는 쪽에 깔끔한 파일명이 보이도록 원래 이름으로 옮겨 둔다.
  /// 실패해도 저장 자체는 끝난 것이므로 null 을 돌려주고 넘어간다.
  static Future<File?> _keepForSharing(File tempFile, String filename) async {
    try {
      final dir = Directory('${tempFile.parent.path}/$_shareCacheName');
      await dir.create(recursive: true);
      return await tempFile.rename(_uniquePath(dir.path, filename).path);
    } on FileSystemException {
      if (await tempFile.exists()) await tempFile.delete();
      return null;
    }
  }

  /// 다운로드 목록은 실행 중에만 유지되므로, 지난 실행의 공유용 사본은 쓸 곳이 없다.
  /// 앱을 켤 때 한 번 비운다.
  static Future<void> clearShareCache() async {
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/$_shareCacheName');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 임시 폴더를 못 읽는 플랫폼(테스트 등)에서는 할 일이 없다.
    }
  }

  /// 같은 이름이 있으면 `이름-2.mp4` 처럼 번호를 붙여 덮어쓰기를 막는다.
  static File _uniquePath(String dir, String filename) {
    final dot = filename.lastIndexOf('.');
    final stem = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';

    var candidate = File('$dir/$filename');
    var counter = 2;
    while (candidate.existsSync()) {
      candidate = File('$dir/$stem-$counter$ext');
      counter++;
    }
    return candidate;
  }
}
