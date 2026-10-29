import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/ig_post.dart';
import 'network_thumb.dart';

/// 사진·영상 위에 댓글을 둥근 말풍선으로 하나씩 차례로 띄운다.
///
/// 평소에는 일정한 간격으로 다음 댓글을 아래에 붙이고, 오래된 것은 위로 밀려 흐려지다
/// 사라진다. [highlighted] 가 있으면(댓글 읽어주기 중) 그 댓글까지 보여 주고 강조한다.
/// 터치는 아래 미디어로 그대로 넘긴다.
class CommentOverlay extends StatefulWidget {
  const CommentOverlay({
    super.key,
    required this.comments,
    this.highlighted,
    this.interval = const Duration(milliseconds: 2600),
  });

  final List<IgPost> comments;

  /// 지금 읽는 댓글의 순번. 읽고 있지 않으면 null.
  final int? highlighted;

  /// 다음 댓글을 띄우는 간격.
  final Duration interval;

  @override
  State<CommentOverlay> createState() => _CommentOverlayState();
}

class _CommentOverlayState extends State<CommentOverlay> {
  /// 마지막으로 띄운 댓글의 순번.
  int _shown = 0;
  Timer? _timer;

  /// 끝까지 띄운 뒤 처음부터 다시 돌기 전에 한 번 쉰다.
  bool _resting = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(CommentOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.comments, widget.comments)) {
      _shown = 0;
      _resting = false;
    }
    // 읽기가 끝나면 마지막으로 읽은 댓글 다음부터 이어서 띄운다.
    if (oldWidget.highlighted != null && widget.highlighted == null) {
      _shown = oldWidget.highlighted!.clamp(0, widget.comments.length - 1);
    }
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    final run = widget.highlighted == null && widget.comments.length > 1;
    if (!run) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(widget.interval, (_) => _advance());
    }
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      if (_resting) {
        _resting = false;
        _shown = 0;
      } else if (_shown < widget.comments.length - 1) {
        _shown++;
      } else {
        _resting = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final comments = widget.comments;
    if (comments.isEmpty) return const SizedBox.shrink();

    final highlighted = widget.highlighted;
    final last = (highlighted ?? _shown).clamp(0, comments.length - 1);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 작은 미리보기(캐러셀 줄)에서는 두 개까지만 쌓는다.
          final maxVisible = constraints.maxHeight < 260 ? 2 : 3;
          final first = (last - maxVisible + 1).clamp(0, last);
          final visible = [for (var i = first; i <= last; i++) i];

          return Align(
            alignment: Alignment.bottomLeft,
            child: AnimatedOpacity(
              opacity: _resting && highlighted == null ? 0 : 1,
              duration: const Duration(milliseconds: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (slot, index) in visible.indexed)
                    Padding(
                      key: ValueKey(index),
                      padding: const EdgeInsets.only(top: 6),
                      child: _Bubble(
                        post: comments[index],
                        highlighted: index == highlighted,
                        // 위로 밀려날수록 흐리게. 강조 중에는 강조된 것만 또렷하게.
                        opacity: highlighted != null
                            ? (index == highlighted ? 1 : 0.55)
                            : const [0.5, 0.8, 1.0][slot + 3 - visible.length],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.post,
    required this.highlighted,
    required this.opacity,
  });

  final IgPost post;
  final bool highlighted;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final foreground = highlighted ? Colors.black : Colors.white;

    final bubble = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.94)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SizedBox(
              width: 24,
              height: 24,
              child: NetworkThumb(
                url: post.user?.profilePicUrl,
                icon: Icons.person_outline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${post.authorName}  ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: post.caption ?? ''),
                ],
              ),
              maxLines: highlighted ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 13, height: 1.35),
            ),
          ),
          if (highlighted) ...[
            const SizedBox(width: 6),
            const Icon(Icons.volume_up, size: 16, color: Colors.black),
          ],
        ],
      ),
    );

    // 새로 붙는 말풍선은 아래에서 살짝 올라오며 나타난다.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t * opacity,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: Transform.scale(
            scale: highlighted ? 1.03 : 1,
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
      child: bubble,
    );
  }
}
