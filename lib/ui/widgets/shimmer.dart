import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// 불러오는 동안 칸 위로 밝은 띠가 지나가는 자리 표시자.
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

class _ShimmerBoxState extends State<ShimmerBox> {
  /// 끝내 안 오는 이미지 때문에 계속 돌지 않도록 [ShimmerBox.timeout] 만큼만 반짝인다.
  late final Timer _stop = Timer(widget.timeout, () {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.timedOut;
    if (_timedOut && fallback != null) return fallback;
    final scheme = Theme.of(context).colorScheme;
    final base =
        widget.overlay
            ? Colors.white.withValues(alpha: 0)
            : scheme.surfaceContainerHighest;
    final highlight =
        widget.overlay
            ? Colors.white.withValues(alpha: 0.35)
            : Color.lerp(base, scheme.surface, 0.7)!;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1300),
      enabled: !_timedOut,
      child: const ColoredBox(color: Colors.white, child: SizedBox.expand()),
    );
  }
}

/// 장소를 찾는 동안 칩 자리에 보여 주는 두 줄.
class PlaceChipsSkeleton extends StatelessWidget {
  const PlaceChipsSkeleton({super.key});

  static const _rows = [
    [92.0, 68.0, 110.0],
    [76.0, 100.0],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, row) in _rows.indexed) ...[
          if (index > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (final width in row)
                // 폭이 모자라면 칩이 함께 줄어든다.
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        width: width,
                        height: 24,
                        // 분석은 오래 걸릴 수 있어 내내 반짝이게 한다.
                        child: const ShimmerBox(timeout: Duration(minutes: 2)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
