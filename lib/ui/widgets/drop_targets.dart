import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/links_controller.dart';

// 카드를 길게 눌러 끌 때 나오는 놓을 곳들. 링크 화면과 지도 화면이 함께 쓴다.

/// 카드를 끄는 동안 카테고리 줄이 세로 목록으로 펼쳐진 것. 칸마다 카드를 놓으면
/// 그 카테고리로 옮긴다.
///
/// 칸 i 는 가로 줄의 i 번째 자리(오른쪽으로 [_rowStep] 씩)에서 출발해 세로 목록의 i 번째
/// 자리로 내려오고, 접힐 때는 거꾸로 돌아간다.
class CategoryDropPanel<T extends Object> extends StatelessWidget {
  const CategoryDropPanel({
    super.key,
    required this.animation,
    required this.categories,
    required this.current,
    required this.hint,
    required this.canAccept,
    required this.onDrop,
  });

  static const _rowStep = 96.0;
  static const _gap = 8.0;

  final Animation<double> animation;
  final List<String> categories;
  final String current;
  final String hint;

  /// [category] 에 놓을 수 있는지. 지금 카테고리 같은 곳은 막는다.
  final bool Function(T data, String category) canAccept;
  final void Function(T data, String category) onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    final count = categories.length;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value);
        return Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.97 * t),
          elevation: 6 * t,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Opacity(
                    opacity: t,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: Text(
                        hint,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  for (final (i, category) in categories.indexed) ...[
                    _tile(context, i, count, category),
                    if (i < count - 1) const SizedBox(height: _gap),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, int i, int count, String category) {
    // 앞 칸부터 조금씩 늦게 출발해 차례로 내려앉는다.
    final start = count <= 1 ? 0.0 : 0.25 * i / (count - 1);
    final t = Curves.easeOutCubic.transform(
      ((animation.value - start) / (1 - start)).clamp(0.0, 1.0),
    );
    final from = Offset(i * _rowStep, -(i * (_tileHeight + _gap)) - 24);
    final isCurrent = category == current;
    return Transform.translate(
      offset: Offset.lerp(from, Offset.zero, t)!,
      child: Opacity(
        opacity: t,
        child: DragTarget<T>(
          onWillAcceptWithDetails: (details) =>
              canAccept(details.data, category),
          onAcceptWithDetails: (details) => onDrop(details.data, category),
          builder: (context, candidates, _) => _CategoryDropTile(
            label: category,
            isCurrent: isCurrent,
            hovering: candidates.isNotEmpty,
          ),
        ),
      ),
    );
  }
}

const _tileHeight = 48.0;

class _CategoryDropTile extends StatelessWidget {
  const _CategoryDropTile({
    required this.label,
    required this.isCurrent,
    required this.hovering,
  });

  final String label;
  final bool isCurrent;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = context.select<LinksController, int>(
      (controller) => controller.countIn(label),
    );
    return AnimatedScale(
      scale: hovering ? 1.04 : 1,
      duration: const Duration(milliseconds: 140),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: _tileHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: hovering
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hovering ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.check : Icons.folder_outlined,
              size: 20,
              color: isCurrent ? scheme.onSurfaceVariant : scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isCurrent ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
            ),
            Text('$count', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 아래쪽 점선 쓰레기통. 카드를 놓으면 지운다.
class TrashDropZone<T extends Object> extends StatelessWidget {
  const TrashDropZone({
    super.key,
    required this.animation,
    required this.label,
    required this.onDrop,
  });

  final Animation<double> animation;
  final String label;
  final ValueChanged<T> onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(animation.value);
        return Transform.translate(
          offset: Offset(0, (1 - t) * 120),
          child: Opacity(opacity: animation.value, child: child),
        );
      },
      child: DragTarget<T>(
        onAcceptWithDetails: (details) => onDrop(details.data),
        builder: (context, candidates, _) {
          final hovering = candidates.isNotEmpty;
          final color = hovering ? scheme.error : scheme.onSurfaceVariant;
          return AnimatedScale(
            scale: hovering ? 1.06 : 1,
            duration: const Duration(milliseconds: 140),
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: color,
                radius: 18,
                fill: hovering
                    ? scheme.errorContainer
                    : scheme.surface.withValues(alpha: 0.95),
              ),
              child: SizedBox(
                height: 72,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hovering ? Icons.delete : Icons.delete_outline,
                      color: color,
                      size: hovering ? 30 : 26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.fill,
  });

  final Color color;
  final double radius;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 8.0;
    const gap = 6.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.fill != fill || old.radius != radius;
}
