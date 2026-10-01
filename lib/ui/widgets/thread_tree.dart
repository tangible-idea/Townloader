import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/ig_post.dart';
import '../../models/threads_thread.dart';
import '../format.dart';
import 'network_thumb.dart';

/// Threads 스레드를 본문 → 이어지는 글 → 댓글 순의 트리로 보여 주고,
/// 본문 미디어만 받을지 댓글까지 전부 받을지 고르게 한다.
class ThreadTree extends StatelessWidget {
  const ThreadTree({super.key, required this.thread, required this.onDownload});

  final ThreadsThread thread;

  /// 고른 글들의 미디어를 다운로드 큐에 넣는다.
  final void Function(List<IgPost> posts) onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choices(context),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, node) in thread.nodes.indexed)
                  _ThreadNodeTile(
                    node: node,
                    // 다음 글이 같은 깊이이거나 더 깊으면(답글) 세로선을 이어 그린다.
                    connectsBelow:
                        index + 1 < thread.nodes.length &&
                        thread.nodes[index + 1].depth >= node.depth,
                    onDownload: node.post.hasDownloadableAssets
                        ? () => onDownload([node.post])
                        : null,
                  ),
                if (thread.hasMoreReplies)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      S.of(context).moreRepliesHidden,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _choices(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final main = thread.mainPosts;
    final all = thread.allPosts;
    final mainFiles = ThreadsThread.fileCount(main);
    final allFiles = ThreadsThread.fileCount(all);
    final authorPosts = thread.nodes.where((node) => node.isMain).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.threadSummary(authorPosts, thread.replyCount),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              allFiles == 0 ? s.noThreadMedia : s.mainMediaHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (allFiles > 0) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: mainFiles == 0 ? null : () => onDownload(main),
                icon: const Icon(Icons.download),
                label: Text(s.downloadMainMedia(mainFiles)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                // 댓글에 미디어가 없으면 본문과 같으므로 굳이 누를 이유가 없다.
                onPressed: allFiles == mainFiles ? null : () => onDownload(all),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(s.downloadAllMedia(allFiles)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThreadNodeTile extends StatelessWidget {
  const _ThreadNodeTile({
    required this.node,
    required this.connectsBelow,
    required this.onDownload,
  });

  final ThreadNode node;
  final bool connectsBelow;
  final VoidCallback? onDownload;

  static const _avatar = 32.0;
  static const _indent = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final post = node.post;
    final line = theme.colorScheme.outlineVariant;

    final badge = switch (node.role) {
      ThreadRole.root => s.threadRoot,
      ThreadRole.continuation => s.threadContinuation,
      ThreadRole.reply => s.threadReply,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 16 + node.depth * _indent),
          // 아바타와 그 아래로 이어지는 세로선.
          SizedBox(
            width: _avatar,
            child: Column(
              children: [
                const SizedBox(height: 10),
                ClipOval(
                  child: SizedBox.square(
                    dimension: _avatar,
                    child: NetworkThumb(
                      url: post.user?.profilePicUrl,
                      icon: Icons.person_outline,
                    ),
                  ),
                ),
                Expanded(
                  child: connectsBelow
                      ? Container(width: 2, color: line)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@${post.authorName}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _Badge(
                        label: badge,
                        strong: node.role != ThreadRole.reply,
                      ),
                    ],
                  ),
                  if (post.caption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      // 빈 줄도 줄 수 제한을 차지해 미디어와 사이가 벌어지므로 접는다.
                      post.caption!.replaceAll(RegExp(r'\n\s*\n+'), '\n'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (post.hasDownloadableAssets) ...[
                    const SizedBox(height: 8),
                    _MediaStrip(post: post),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: onDownload == null
                ? null
                : Align(
                    alignment: Alignment.topCenter,
                    child: IconButton(
                      tooltip: s.downloadThisPost,
                      icon: const Icon(Icons.download_outlined, size: 20),
                      onPressed: onDownload,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.strong});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: strong ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: strong ? scheme.onPrimary : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 글에 붙은 사진·동영상을 작은 썸네일 줄로 보여 준다.
class _MediaStrip extends StatelessWidget {
  const _MediaStrip({required this.post});

  final IgPost post;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final items = post.items.where((item) => item.hasAssets).toList();

    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = items[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: _size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkThumb(
                    url: item.thumbnailUrl ?? item.best?.url,
                    icon: item.isVideo
                        ? Icons.movie_outlined
                        : Icons.image_outlined,
                  ),
                  if (item.isVideo)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          Fmt.duration(item.durationSeconds).isEmpty
                              ? '▶'
                              : Fmt.duration(item.durationSeconds),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
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
}
