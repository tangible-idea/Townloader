import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/ig_post.dart';
import 'network_thumb.dart';

/// 카드 안에서 크게 보여 주는 동영상. 처음엔 썸네일과 재생 버튼만 두고,
/// 누르면 그 자리에서 재생한다. 다시 누르면 멈춘다.
///
/// 목록에 여러 개가 있어도 누른 것만 플레이어를 만들어 메모리를 아낀다.
class InlineVideo extends StatefulWidget {
  const InlineVideo({super.key, required this.item});

  final IgItem item;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final existing = _controller;
    if (existing != null) {
      if (!existing.value.isInitialized) return;
      existing.value.isPlaying ? await existing.pause() : await existing.play();
      if (mounted) setState(() {});
      return;
    }

    final url = widget.item.best?.url;
    if (url == null) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    setState(() => _controller = controller);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      // 준비되는 사이에 화면에서 사라졌을 수 있다.
      if (!mounted) return;
      await controller.play();
      controller.addListener(_onTick);
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    // 재생/정지 표시만 갱신한다.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final playing = ready && controller.value.isPlaying;
    final loading = controller != null && !ready && !_failed;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _failed ? null : _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            ColoredBox(
              color: Colors.black,
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: controller.value.size,
                  child: VideoPlayer(controller),
                ),
              ),
            )
          else
            NetworkThumb(
              url: widget.item.thumbnailUrl,
              icon: Icons.movie_outlined,
            ),
          if (!playing)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _failed ? Icons.error_outline : Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
