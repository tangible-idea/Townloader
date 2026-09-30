import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../services/download_service.dart';
import 'format.dart';
import 'widgets/network_thumb.dart';
import 'widgets/state_views.dart';

/// 진행 중이거나 끝난 다운로드 목록.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final downloads = context.watch<DownloadService>();
    final items = downloads.items;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.downloadsTitle),
        actions: [
          if (items.any((item) => item.status.isFinished))
            TextButton.icon(
              onPressed: downloads.clearFinished,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: Text(s.clearFinished),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: items.isEmpty
            ? MessageView(
                icon: Icons.download_done_outlined,
                title: s.noDownloadsTitle,
                description: s.noDownloadsDesc,
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _DownloadTile(item: items[index]),
                  ),
                ),
              ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.item});

  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloads = context.read<DownloadService>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 52,
                child: NetworkThumb(
                  url: item.thumbnailUrl,
                  icon: item.asset.isVideo
                      ? Icons.movie_outlined
                      : Icons.image_outlined,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    item.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _statusLine(context),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _trailing(context, downloads),
          ],
        ),
      ),
    );
  }

  Widget _statusLine(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);

    switch (item.status) {
      case DownloadStatus.queued:
        return Text(
          s.queued,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );

      case DownloadStatus.running:
        final received = Fmt.bytes(item.receivedBytes);
        final total = Fmt.bytes(item.totalBytes);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress,
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              total.isEmpty ? received : '$received / $total',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case DownloadStatus.completed:
        final location = item.savedLocation;
        return Row(
          children: [
            Icon(
              Icons.check_circle,
              size: 15,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                location?.description ?? (s.isKo ? '완료' : 'Done'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );

      case DownloadStatus.failed:
        return Row(
          children: [
            Icon(Icons.error_outline, size: 15, color: theme.colorScheme.error),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                item.errorMessage ?? s.failed,
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        );

      case DownloadStatus.canceled:
        return Text(
          s.cancel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
    }
  }

  Widget _trailing(BuildContext context, DownloadService downloads) {
    final s = S.of(context);
    if (item.isActive) {
      return IconButton(
        tooltip: s.cancel,
        icon: const Icon(Icons.close),
        onPressed: () => downloads.cancel(item.id),
      );
    }

    if (item.status == DownloadStatus.completed) {
      final location = item.savedLocation;
      final path = location?.filePath;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (location?.sharePath != null) ...[
            // iOS 는 AirDrop 을 곧바로 여는 공개 API 가 없어, 다른 기본 항목을 뺀
            // 공유 시트를 띄워 AirDrop 이 맨 앞에 오게 한다.
            if (_isIOS)
              IconButton(
                tooltip: s.airDrop,
                icon: const Icon(Icons.wifi_tethering),
                onPressed: () => _share(context, airDropOnly: true),
              ),
            IconButton(
              tooltip: s.share,
              icon: const Icon(Icons.ios_share),
              onPressed: () => _share(context, airDropOnly: false),
            ),
          ],
          // 모바일에서 앨범에 넣은 경우에는 복사할 경로가 없다.
          if (path != null)
            IconButton(
              tooltip: s.openFolder,
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: path));
                if (context.mounted) {
                  _toast(context, s.isKo ? '경로 복사됨' : 'Path copied');
                }
              },
            ),
        ],
      );
    }

    return IconButton(
      tooltip: s.retry,
      icon: const Icon(Icons.refresh),
      onPressed: () => downloads.retry(item.id),
    );
  }

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  /// AirDrop 만 남기려고 공유 시트에서 빼는 기본 항목들.
  static final _allButAirDrop = [
    for (final type in CupertinoActivityType.values)
      if (type != CupertinoActivityType.airDrop) type,
  ];

  Future<void> _share(BuildContext context, {required bool airDropOnly}) async {
    final s = S.of(context);
    final path = item.savedLocation?.sharePath;
    // 아이패드·맥은 공유 시트를 띄울 기준 위치가 필요하다.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    // 캐시에 둔 사본은 저장 공간이 부족하면 OS 가 지울 수 있다.
    if (path == null || !await File(path).exists()) {
      if (context.mounted) _toast(context, s.shareUnavailable);
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        sharePositionOrigin: origin,
        excludedCupertinoActivities: airDropOnly ? _allButAirDrop : null,
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
