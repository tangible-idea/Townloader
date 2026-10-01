import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/ig_post.dart';
import '../../services/download_service.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import 'download_options_sheet.dart';
import 'inline_video.dart';
import 'network_thumb.dart';

/// 해석된 게시물 하나를 미리보기와 다운로드 버튼으로 보여준다.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final IgPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          _preview(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.caption != null) ...[
                  Text(
                    post.caption!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                _stats(context),
                const SizedBox(height: 14),
                _actions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final user = post.user;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: NetworkThumb(
                  url: user?.profilePicUrl,
                  icon: Icons.person_outline,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '@${post.authorName}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (user?.isVerified ?? false) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                Text(
                  [
                    post.kind.localizedLabel(S.of(context).isKo),
                    if (post.items.length > 1)
                      S.of(context).itemsCount(post.items.length),
                    Fmt.date(post.takenAt),
                  ].where((text) => text.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (post.permalink != null)
            IconButton(
              tooltip: S.of(context).copyLink,
              icon: const Icon(Icons.link, size: 20),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: post.permalink!));
                if (context.mounted) {
                  _toast(context, S.of(context).linkCopied);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context) {
    // 캐러셀은 가로로 넘겨 보고, 단일 항목은 크게 한 장만 보여준다.
    if (post.items.length > 1) {
      return SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: post.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = post.items[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkThumb(url: item.thumbnailUrl),
                    if (item.isVideo)
                      const Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.play_circle_fill,
                            size: 20,
                            color: Colors.white,
                          ),
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

    final item = post.items.first;
    // 원본 비율로 크게 보여 준다. 너무 길거나 넓은 건 화면을 다 차지하지 않게 자른다.
    final best = item.best;
    final width = best?.width;
    final height = best?.height;
    final ratio = width != null && height != null && width > 0 && height > 0
        ? (width / height).clamp(
            item.isVideo ? _tallestVideoRatio : _tallestPhotoRatio,
            _widestRatio,
          )
        : 4 / 3;

    // 넓은 화면에서 세로 영상이 끝없이 길어지지 않도록 화면 높이의 70% 로 막는다.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.isVideo)
                InlineVideo(item: item)
              else
                NetworkThumb(url: item.thumbnailUrl ?? best?.url),
              if (item.isVideo &&
                  item.durationSeconds != null &&
                  item.durationSeconds! > 0)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: _pill(Fmt.duration(item.durationSeconds)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 세로 사진은 4:5, 가로는 1.91:1 까지만 보여 준다(인스타그램 피드와 같다).
  /// 세로 동영상은 잘리거나 작아지지 않도록 9:16 그대로 크게 보여 준다.
  static const double _tallestPhotoRatio = 4 / 5;
  static const double _tallestVideoRatio = 9 / 16;
  static const double _widestRatio = 1.91;

  Widget _stats(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <(IconData, String)>[
      if ((post.likeCount ?? 0) > 0)
        (
          Icons.favorite_border,
          Fmt.count(post.likeCount, isKo: S.of(context).isKo),
        ),
      if ((post.commentCount ?? 0) > 0)
        (
          Icons.mode_comment_outlined,
          Fmt.count(post.commentCount, isKo: S.of(context).isKo),
        ),
      if ((post.playCount ?? post.viewCount ?? 0) > 0)
        (
          Icons.play_arrow_outlined,
          Fmt.count(post.playCount ?? post.viewCount, isKo: S.of(context).isKo),
        ),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 16,
      children: [
        for (final (icon, value) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final s = S.of(context);
    final hasVariantChoice = post.items.any((item) => item.variants.length > 1);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              final settings = context.read<SettingsController>();
              final count = context.read<DownloadService>().enqueuePost(
                post,
                quality: settings.quality,
              );
              _toast(context, s.downloadStarted(count));
            },
            icon: const Icon(Icons.download),
            label: Text(
              post.items.length > 1
                  ? '${s.downloadAll} (${post.items.length})'
                  : s.downloadBtn,
            ),
          ),
        ),
        if (hasVariantChoice) ...[
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: s.selectQuality,
            icon: const Icon(Icons.tune),
            onPressed: () => DownloadOptionsSheet.show(context, post),
          ),
        ],
      ],
    );
  }

  static Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
