import 'package:flutter/material.dart';

import 'shimmer.dart';

/// 아이콘 + 설명 + (선택) 버튼으로 이뤄진 빈 상태 / 오류 화면.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 읽기 탭에서 글을 처음 불러오는 동안 결과 자리에 보여 주는 뼈대.
class ReaderLoadingView extends StatelessWidget {
  const ReaderLoadingView({super.key, this.label});

  /// 화면 낭독기가 읽을 설명.
  final String? label;

  static Widget _bar(double widthFactor, {double height = 12}) =>
      FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: _box(height: height, radius: height / 2),
      );

  /// 느린 응답에도 멈춰 보이지 않게 시머를 요청 제한 시간 동안 돌린다.
  static Widget _box({double? width, double? height, double radius = 8}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: height,
          child: const ShimmerBox(timeout: Duration(minutes: 1)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Semantics(
          label: label,
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _bar(0.55, height: 18),
              const SizedBox(height: 16),
              Row(
                children: [
                  _box(width: 36, height: 36, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(child: _bar(0.4)),
                ],
              ),
              const SizedBox(height: 12),
              _bar(1),
              const SizedBox(height: 8),
              _bar(1),
              const SizedBox(height: 8),
              _bar(0.7),
              const SizedBox(height: 16),
              AspectRatio(aspectRatio: 4 / 3, child: _box(radius: 12)),
              const SizedBox(height: 20),
              _bar(1),
              const SizedBox(height: 8),
              _bar(0.8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 화면 전체를 덮는 진행 표시.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(
              label!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
