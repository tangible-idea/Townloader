import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../data/poe_tts_client.dart';

/// 오디오 하나를 끝까지 재생한다. 테스트에서는 가짜로 바꿔 끼운다.
abstract class AudioPlayback {
  /// 재생이 끝나면(또는 [stop] 되면) 완료된다.
  Future<void> play(Uri url);

  Future<void> stop();

  void dispose();
}

/// 이미 쓰고 있는 video_player 로 오디오만 재생한다(화면은 붙이지 않는다).
class VideoPlayerAudioPlayback implements AudioPlayback {
  VideoPlayerController? _controller;
  Completer<void>? _done;

  @override
  Future<void> play(Uri url) async {
    await stop();
    final controller = VideoPlayerController.networkUrl(url);
    final done = Completer<void>();
    _controller = controller;
    _done = done;

    void onTick() {
      final value = controller.value;
      final finished =
          value.isInitialized &&
          value.duration > Duration.zero &&
          !value.isPlaying &&
          value.position >= value.duration;
      if ((finished || value.hasError) && !done.isCompleted) done.complete();
    }

    controller.addListener(onTick);
    await controller.initialize();
    if (_controller != controller) return; // 준비되는 사이 멈췄다.
    await controller.play();
    return done.future;
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    if (_done case final done? when !done.isCompleted) done.complete();
    _done = null;
    await controller?.dispose();
  }

  @override
  void dispose() => unawaited(stop());
}

/// 댓글을 차례로 소리 내어 읽는다.
///
/// 지금 글을 읽는 동안 다음 글의 음성을 미리 만들어 두어 사이가 끊기지 않게 한다.
class CommentReader extends ChangeNotifier {
  CommentReader({required this.synthesize, AudioPlayback? playback})
    : _playback = playback ?? VideoPlayerAudioPlayback();

  /// 글 → 오디오 주소. 보통 [PoeTtsClient.synthesize].
  final Future<Uri> Function(String text) synthesize;
  final AudioPlayback _playback;

  int? _current;
  bool _loading = false;
  String? _error;

  /// 읽기를 시작할 때마다 바뀐다. 멈춘 뒤에 끝난 이전 작업이 상태를 건드리지 않게 한다.
  int _session = 0;

  /// 지금 읽는(또는 음성을 만드는) 글의 순번. 읽고 있지 않으면 null.
  int? get current => _current;
  bool get isActive => _current != null;

  /// 지금 글의 음성을 만드는 중인지.
  bool get isLoading => _loading;
  String? get error => _error;

  /// [texts] 를 [from] 번째부터 끝까지 읽는다. 빈 글은 건너뛴다.
  Future<void> start(List<String> texts, {int from = 0}) async {
    final session = ++_session;
    await _playback.stop();
    _error = null;

    Future<Uri>? next;
    Future<Uri>? prepare(int index) {
      if (index >= texts.length) return null;
      final future = synthesize(texts[index]);
      // 미리 만든 것이 쓰이지 않고 실패해도 처리되지 않은 오류로 남지 않게 한다.
      future.ignore();
      return future;
    }

    for (var i = from; i < texts.length; i++) {
      if (session != _session) return;
      if (texts[i].trim().isEmpty) continue;

      _current = i;
      _loading = true;
      notifyListeners();

      try {
        final url = await (next ?? synthesize(texts[i]));
        if (session != _session) return;
        next = prepare(_nextReadable(texts, i + 1));
        _loading = false;
        notifyListeners();
        await _playback.play(url);
      } catch (error) {
        if (session != _session) return;
        _error = error.toString();
        break;
      }
    }

    if (session != _session) return;
    _current = null;
    _loading = false;
    notifyListeners();
  }

  int _nextReadable(List<String> texts, int from) {
    var index = from;
    while (index < texts.length && texts[index].trim().isEmpty) {
      index++;
    }
    return index;
  }

  Future<void> stop() async {
    _session++;
    _current = null;
    _loading = false;
    notifyListeners();
    await _playback.stop();
  }

  @override
  void dispose() {
    _session++;
    _playback.dispose();
    super.dispose();
  }
}
