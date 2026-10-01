import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/ig_post.dart';
import 'network_thumb.dart';

/// 길게 누르는 동안만 글의 미디어를 크게 띄운다. 손을 떼면 바로 닫힌다.
///
/// 동영상이면 곧바로 재생하고, 닫히면 플레이어도 함께 정리한다.
class PeekOnLongPress extends StatefulWidget {
  const PeekOnLongPress({super.key, required this.post, required this.child});

  final IgPost post;
  final Widget child;

  @override
  State<PeekOnLongPress> createState() => _PeekOnLongPressState();
}

class _PeekOnLongPressState extends State<PeekOnLongPress> {
  OverlayEntry? _entry;

  void _open() {
    if (_entry != null) return;
    HapticFeedback.mediumImpact();
    _entry = OverlayEntry(builder: (_) => _PeekOverlay(post: widget.post));
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _open(),
      onLongPressEnd: (_) => _close(),
      onLongPressCancel: _close,
      child: widget.child,
    );
  }
}

class _PeekOverlay extends StatelessWidget {
  const _PeekOverlay({required this.post});

  final IgPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = post.items.where((item) => item.hasAssets).firstOrNull;
    final caption = post.caption;

    // 손가락이 미리보기 위에 있어도 길게 누르기 제스처가 끊기지 않도록
    // 오버레이는 터치를 받지 않는다.
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.55 * t),
            child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (item != null) Flexible(child: _PeekMedia(item: item)),
                      if (caption != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Text(
                            caption,
                            maxLines: item == null ? 12 : 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진은 원본을, 동영상은 바로 재생한다. 동영상이 준비될 때까지는 썸네일을 보인다.
class _PeekMedia extends StatefulWidget {
  const _PeekMedia({required this.item});

  final IgItem item;

  @override
  State<_PeekMedia> createState() => _PeekMediaState();
}

class _PeekMediaState extends State<_PeekMedia> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    final url = widget.item.best?.url;
    if (widget.item.isVideo && url != null) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _video = controller;
      controller.setLooping(true);
      controller
          .initialize()
          .then((_) {
            // 준비되기 전에 손을 떼서 이미 닫혔을 수 있다.
            if (!mounted) return;
            controller.play();
            setState(() {});
          })
          .catchError((_) {
            // 재생에 실패하면 썸네일만 보여 준다.
          });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final video = _video;
    final best = item.best;

    if (video != null && video.value.isInitialized) {
      return AspectRatio(
        aspectRatio: video.value.aspectRatio,
        child: VideoPlayer(video),
      );
    }

    final width = best?.width;
    final height = best?.height;
    final ratio = width != null && height != null && width > 0 && height > 0
        ? width / height
        : (item.isVideo ? 9 / 16 : 1.0);

    return AspectRatio(
      aspectRatio: ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkThumb(
            // 사진은 원본, 동영상은 준비될 때까지 썸네일.
            url: item.isVideo
                ? item.thumbnailUrl
                : (best?.url ?? item.thumbnailUrl),
            fit: BoxFit.contain,
            icon: item.isVideo ? Icons.movie_outlined : Icons.image_outlined,
          ),
          if (video != null)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
