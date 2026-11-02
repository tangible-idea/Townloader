import 'dart:async';

import 'package:flutter/material.dart';

/// 불러오는 동안 칸 위로 밝은 띠가 비스듬히 지나가는 자리 표시자.
///
/// [overlay] 면 바탕 없이 띠만 그려, 썸네일 위에 얹어 영상을 준비 중임을 알린다.
/// [timeout] 이 지나도록 그대로면 반짝임을 멈추고, [timedOut] 이 있으면 그것으로 바꾼다.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.overlay = false,
    this.timeout = const Duration(seconds: 10),
    this.timedOut,
  });

  final bool overlay;
  final Duration timeout;
  final Widget? timedOut;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  /// 끝내 안 오는 이미지 때문에 계속 돌지 않도록 [ShimmerBox.timeout] 만큼만 반짝인다.
  late final Timer _stop = Timer(widget.timeout, () {
    _controller.stop();
    if (mounted) setState(() => _timedOut = true);
  });
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _stop;
  }

  @override
  void dispose() {
    _stop.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.timedOut;
    if (_timedOut && fallback != null) return fallback;
    final scheme = Theme.of(context).colorScheme;
    final base = widget.overlay
        ? Colors.white.withValues(alpha: 0)
        : scheme.surfaceContainerHighest;
    final highlight = widget.overlay
        ? Colors.white.withValues(alpha: 0.35)
        : Color.lerp(base, scheme.surface, 0.7)!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 띠가 칸 왼쪽 밖에서 출발해 오른쪽 밖으로 빠져나간다.
        final t = _controller.value * 3 - 1;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(t - 1, -0.3),
              end: Alignment(t + 1, 0.3),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
