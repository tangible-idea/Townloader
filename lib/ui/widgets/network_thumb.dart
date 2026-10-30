import 'package:flutter/material.dart';

import '../../services/image_disk_cache.dart';

/// 인스타그램 CDN 썸네일을 안전하게 그린다.
///
/// CDN URL 은 서명이 만료되면 403 을 돌려주므로, 실패했을 때 깨진 아이콘 대신
/// 자리 표시자를 보여주는 것이 중요하다.
class NetworkThumb extends StatelessWidget {
  const NetworkThumb({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.icon = Icons.image_outlined,
  });

  final String? url;
  final BoxFit fit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = url;

    if (source == null || source.isEmpty) return _placeholder(scheme);

    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        return Image(
          image: DiskCachedImage(
            source,
            targetWidth: _physical(constraints.maxWidth, ratio),
            targetHeight: _physical(constraints.maxHeight, ratio),
          ),
          fit: fit,
          gaplessPlayback: true,
          // 디스크에서 읽는 짧은 순간에는 빈 바탕만, 실제로 내려받을 때만 스피너를 보인다.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) return child;
            return ColoredBox(color: scheme.surfaceContainerHighest);
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _placeholder(scheme),
        );
      },
    );
  }

  /// 디코딩 크기. 크기가 조금씩 바뀔 때마다 새로 디코딩하지 않도록 64px 단위로 올린다.
  static int? _physical(double logical, double ratio) {
    if (!logical.isFinite || logical <= 0) return null;
    return ((logical * ratio) / 64).ceil() * 64;
  }

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Center(
      child: Icon(icon, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
    ),
  );
}
