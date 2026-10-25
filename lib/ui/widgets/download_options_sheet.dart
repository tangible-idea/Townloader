import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ig_asset.dart';
import '../../models/ig_post.dart';
import '../../services/download_service.dart';
import '../format.dart';
import 'network_thumb.dart';
import 'personal_use_notice.dart';

/// 게시물 항목마다 화질을 직접 골라 받게 해 주는 시트.
///
/// 릴스는 보통 3~4가지 해상도가 오고, 캐러셀은 슬라이드마다 선택이 다를 수 있어
/// 항목별로 따로 고르게 한다.
class DownloadOptionsSheet extends StatefulWidget {
  const DownloadOptionsSheet({super.key, required this.post});

  final IgPost post;

  static Future<void> show(BuildContext context, IgPost post) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DownloadOptionsSheet(post: post),
    );
  }

  @override
  State<DownloadOptionsSheet> createState() => _DownloadOptionsSheetState();
}

class _DownloadOptionsSheetState extends State<DownloadOptionsSheet> {
  /// 항목 인덱스 → 선택된 변형. 기본값은 각 항목의 최고 화질.
  late final Map<int, IgAsset> _selection = {
    for (var i = 0; i < widget.post.items.length; i++)
      if (widget.post.items[i].best != null) i: widget.post.items[i].best!,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.post.items;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                '화질 선택',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 24),
                itemBuilder: (context, index) =>
                    _itemRow(context, items[index], index),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: FilledButton.icon(
                onPressed: _selection.isEmpty ? null : _downloadSelected,
                icon: const Icon(Icons.download),
                label: Text('선택한 ${_selection.length}개 받기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(BuildContext context, IgItem item, int index) {
    final theme = Theme.of(context);
    final selected = _selection[index];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: NetworkThumb(
              url: item.thumbnailUrl,
              icon: item.isVideo
                  ? Icons.play_circle_outline
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
                widget.post.items.length > 1
                    ? '${index + 1}번째 · ${item.isVideo ? '동영상' : '사진'}'
                    : (item.isVideo ? '동영상' : '사진'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (item.variants.length <= 1)
                Text(
                  _variantLabel(selected ?? item.variants.first),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                DropdownButtonFormField<IgAsset>(
                  initialValue: selected,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    for (final variant in item.variants)
                      DropdownMenuItem(
                        value: variant,
                        child: Text(_variantLabel(variant)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selection[index] = value);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// `1080×1920 · 0.9 Mbps` 처럼 고를 수 있는 정보를 최대한 보여준다.
  static String _variantLabel(IgAsset asset) {
    final parts = <String>[];
    final resolution = asset.resolutionLabel;
    if (resolution != null) parts.add(resolution);

    final bandwidth = asset.bandwidth;
    if (bandwidth != null && bandwidth > 0) {
      parts.add('${(bandwidth / 1000000).toStringAsFixed(1)} Mbps');
    }
    final duration = Fmt.duration(asset.durationSeconds);
    if (duration.isNotEmpty) parts.add(duration);

    return parts.isEmpty ? '원본' : parts.join(' · ');
  }

  Future<void> _downloadSelected() async {
    if (!await confirmPersonalUse(context) || !mounted) return;
    final downloads = context.read<DownloadService>();
    for (final entry in _selection.entries) {
      downloads.enqueueAsset(
        widget.post,
        entry.value,
        index: entry.key,
        thumbnailUrl: widget.post.items[entry.key].thumbnailUrl,
      );
    }
    Navigator.of(context).pop();
  }
}
