import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/maps_client.dart';
import 'links_controller.dart';

/// 지도 동기화 계정. 로그인하면 Links 탭의 링크를 서버에 올려 두고, 카테고리를
/// 공유하면 그 카테고리를 public 으로 바꾼다.
///
/// 동기화는 마지막에 쓴 쪽이 이기는 방식이다. 로그인할 때 서버 것을 기기에 합치고,
/// 그 뒤로는 기기에서 바뀔 때마다 잠시 모았다가 통째로 올린다.
class AccountController extends ChangeNotifier {
  AccountController({
    required MapsClient client,
    required LinksController links,
    required Future<String?> Function() readSession,
    required Future<bool> Function(String? value) writeSession,
    this.uploadDelay = const Duration(seconds: 2),
  }) : _client = client,
       _links = links,
       _readSession = readSession,
       _writeSession = writeSession {
    _links.addListener(_onLinksChanged);
  }

  final MapsClient _client;
  final LinksController _links;
  final Future<String?> Function() _readSession;
  final Future<bool> Function(String? value) _writeSession;
  final Duration uploadDelay;

  MapsSession? _session;
  List<MapShare> _shares = const [];
  bool _busy = false;
  bool _syncing = false;
  String? _error;
  DateTime? _lastSynced;
  int _uploadedRevision = -1;
  Timer? _uploadTimer;

  MapsSession? get session => _session;
  bool get isSignedIn => _session != null;
  List<MapShare> get shares => _shares;

  /// 로그인·로그아웃·계정 삭제처럼 버튼을 막아야 하는 작업 중.
  bool get busy => _busy;
  bool get syncing => _syncing;
  String? get error => _error;
  DateTime? get lastSynced => _lastSynced;

  MapShare? shareOf(String category) {
    for (final share in _shares) {
      if (share.category == category) return share;
    }
    return null;
  }

  /// 저장해 둔 세션이 있으면 이어서 동기화한다. Links 를 읽은 뒤에 부른다.
  Future<void> load() async {
    final raw = await _readSession();
    if (raw == null) return;
    try {
      _session = MapsSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await _writeSession(null);
      return;
    }
    notifyListeners();
    await sync();
  }

  /// [idToken] 은 구글·Apple 이 준 토큰. null 이면 사용자가 취소한 것이다.
  Future<void> signIn(
    String provider,
    Future<String?> Function() idToken,
  ) async {
    if (_busy) return;
    _setBusy(true);
    try {
      final token = await idToken();
      if (token == null) return;
      final session = await _client.signIn(provider: provider, idToken: token);
      _session = session;
      await _writeSession(jsonEncode(session.toJson()));
      _uploadedRevision = -1;
      await sync();
    } on MapsException catch (error) {
      _error = error.message;
    } on Object catch (error) {
      _error = error.toString();
    } finally {
      _setBusy(false);
    }
  }

  /// 서버 것을 기기에 합치고, 합친 결과를 다시 올린다.
  Future<void> sync() async {
    final session = _session;
    if (session == null || _syncing) return;
    _syncing = true;
    _error = null;
    notifyListeners();
    try {
      final remote = await _client.download(session);
      if (remote != null) await _links.mergeFrom(remote);
      await _upload(session);
      _shares = await _client.shares(session);
    } on MapsException catch (error) {
      await _handle(error);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// [category] 를 public 으로 바꾸고 공유 링크를 돌려준다. 지금 기기 내용을 먼저 올려
  /// 받는 사람이 최신 장소를 보게 한다.
  Future<MapShare> share(String category) async {
    final session = _session;
    if (session == null) throw MapsException('로그인이 필요합니다.');
    try {
      await _upload(session);
      final share = await _client.share(session, category);
      _shares = [
        for (final s in _shares)
          if (s.category != category) s,
        share,
      ];
      notifyListeners();
      return share;
    } on MapsException catch (error) {
      await _handle(error);
      rethrow;
    }
  }

  /// 다시 비공개로. 이미 보낸 링크는 더 열리지 않는다.
  Future<void> unshare(String category) async {
    final session = _session;
    final share = shareOf(category);
    if (session == null || share == null) return;
    try {
      await _client.unshare(session, share.id);
      _shares = [
        for (final s in _shares)
          if (s.id != share.id) s,
      ];
      notifyListeners();
    } on MapsException catch (error) {
      await _handle(error);
      rethrow;
    }
  }

  /// 로그아웃해도 기기의 링크는 그대로 남는다.
  Future<void> signOut() async {
    final session = _session;
    if (session == null) return;
    _setBusy(true);
    try {
      await _client.signOut(session);
    } on MapsException {
      // 서버에 못 알려도 기기에서는 끝낸다. 세션은 시간이 지나면 만료된다.
    } finally {
      await _clear();
      _setBusy(false);
    }
  }

  /// 서버의 계정, 동기화한 링크, 공유한 지도를 모두 지운다. 기기의 링크는 남는다.
  Future<void> deleteAccount() async {
    final session = _session;
    if (session == null) return;
    _setBusy(true);
    try {
      await _client.deleteAccount(session);
      await _clear();
    } on MapsException catch (error) {
      _error = error.message;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Links 는 저장보다 화면 알림을 먼저 하기도 해서, 여기서는 바뀐 것을 따지지 않고
  /// 타이머가 끝날 때 [_upload] 가 저장 횟수로 가린다.
  void _onLinksChanged() {
    if (_session == null) return;
    _uploadTimer?.cancel();
    _uploadTimer = Timer(uploadDelay, () async {
      final session = _session;
      if (session == null) return;
      try {
        await _upload(session);
        notifyListeners();
      } on MapsException catch (error) {
        await _handle(error);
        notifyListeners();
      }
    });
  }

  Future<void> _upload(MapsSession session) async {
    final revision = _links.revision;
    if (revision == _uploadedRevision) return;
    await _client.upload(session, _links.data);
    _uploadedRevision = revision;
    _lastSynced = DateTime.now();
  }

  /// 세션이 끝났으면 로그아웃 상태로 돌린다.
  Future<void> _handle(MapsException error) async {
    _error = error.message;
    if (error.unauthorized) await _clear();
  }

  Future<void> _clear() async {
    _uploadTimer?.cancel();
    _session = null;
    _shares = const [];
    _lastSynced = null;
    _uploadedRevision = -1;
    await _writeSession(null);
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    if (value) _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _uploadTimer?.cancel();
    _links.removeListener(_onLinksChanged);
    super.dispose();
  }
}
