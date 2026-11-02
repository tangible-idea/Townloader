import 'package:flutter/material.dart';

import '../../services/image_disk_cache.dart';
import 'shimmer.dart';

/// 인스타그램 CDN 썸네일을 안전하게 그린다.
///
/// CDN URL 은 서명이 만료되면 403 을 돌려주므로, 실패했을 때 깨진 아이콘 대신
/// 자리 표시자를 보여주는 것이 중요하다.
class NetworkThumb extends StatelessWidget {
  const NetworkThumb({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.icon = Icons.landscape_outlined,
    this.shimmer = true,
  });

  /// 이만큼 기다려도 사진이 안 오면 [PhotoPlaceholder] 로 바꾼다.
  static const loadTimeout = Duration(seconds: 8);

  final String? url;
  final BoxFit fit;
  final IconData icon;

  /// false 면 불러오는 동안에도 쉬머 없이 [icon] 플레이스홀더를 두고, 사진이 오는
  /// 즉시 바꾼다(지도 카드).
  final bool shimmer;

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
          // 첫 장면이 나오기 전(내려받거나 디스크에서 읽는 동안)에는 쉬머를 보인다.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) return child;
            if (!shimmer) return PhotoPlaceholder(icon: icon);
            return ShimmerBox(
              timeout: loadTimeout,
              timedOut: PhotoPlaceholder(icon: icon),
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

  Widget _placeholder(ColorScheme scheme) => PhotoPlaceholder(icon: icon);
}

/// 사진이 없거나, 불러오지 못했거나, 너무 오래 걸릴 때 대신 보이는 칸.
/// 은은한 대각선 그라데이션 위에 아이콘 하나. 지도 말풍선도 같은 모양으로 그린다
/// (map/place_card_image.dart).
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.icon = Icons.landscape_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          final size = side.isFinite ? (side * 0.36).clamp(14.0, 40.0) : 24.0;
          return Center(
            child: Icon(
              icon,
              size: size,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          );
        },
      ),
    );
  }
}
