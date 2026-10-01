import 'package:flutter/gestures.dart';
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
  static const _holdDuration = Duration(milliseconds: 250);

  OverlayEntry? _entry;

  void _open(Offset pressedAt) {
    if (_entry != null) return;
    HapticFeedback.mediumImpact();
    _entry = OverlayEntry(
      builder: (_) => _PeekOverlay(post: widget.post, pressedAt: pressedAt),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _onStart(LongPressStartDetails details) => _open(details.globalPosition);

  void _onEnd(LongPressEndDetails details) => _close();

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
    // 기본(500ms)보다 짧게 눌러도 열리도록 인식기를 직접 둔다.
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: _holdDuration),
              (recognizer) {
                recognizer
                  ..onLongPressStart = _onStart
                  ..onLongPressEnd = _onEnd
                  ..onLongPressCancel = _close;
              },
            ),
      },
      child: widget.child,
    );
  }
}

class _PeekOverlay extends StatelessWidget {
  const _PeekOverlay({required this.post, required this.pressedAt});

  final IgPost post;

  /// 누른 자리. 미리보기가 이 지점에서 커져 나온다.
  final Offset pressedAt;

  static const _openDuration = Duration(milliseconds: 320);

  /// 처음 크기. 여기서 살짝 넘쳤다가(easeOutBack) 제자리로 돌아온다.
  static const _startScale = 0.55;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = post.items.where((item) => item.hasAssets).firstOrNull;
    final caption = post.caption;

    // 손가락이 미리보기 위에 있어도 길게 누르기 제스처가 끊기지 않도록
    // 오버레이는 터치를 받지 않는다.
    final screen = MediaQuery.sizeOf(context);
    // 누른 지점을 확대 기준점으로 삼아, 그 글에서 튀어나오는 것처럼 보이게 한다.
    final origin = Alignment(
      (pressedAt.dx / screen.width) * 2 - 1,
      (pressedAt.dy / screen.height) * 2 - 1,
    );

    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _openDuration,
        builder: (context, t, child) {
          // 배경과 투명도는 앞쪽에서 빨리, 크기는 끝까지 easeOutBack 으로 튕기듯.
          final fade = Curves.easeOut.transform((t * 1.8).clamp(0.0, 1.0));
          final grow = Curves.easeOutBack.transform(t);
          return ColoredBox(
            color: Colors.black.withValues(alpha: 0.55 * fade),
            child: Opacity(
              opacity: fade,
              child: Transform.scale(
                scale: _startScale + (1 - _startScale) * grow,
                alignment: origin,
                child: child,
              ),
            ),
          );
        },
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
    final knowsSize =
        width != null && height != null && width > 0 && height > 0;

    final placeholder = Stack(
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
    );

    // 크기를 알면 재생될 때와 같은 비율로 자리를 잡아 화면이 들썩이지 않는다.
    // 모르면 크게 잡았다가 줄어들지 않도록 작은 자리만 차지한다.
    if (knowsSize) {
      return AspectRatio(aspectRatio: width / height, child: placeholder);
    }
    return SizedBox(height: _unknownSizeHeight, child: placeholder);
  }

  static const _unknownSizeHeight = 180.0;
}
