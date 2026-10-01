import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/ig_post.dart';
import '../../models/threads_thread.dart';
import 'network_thumb.dart';

/// Threads 스레드를 한눈에 훑어볼 수 있게 촘촘한 목록으로 보여 주고,
/// 링크한 글의 미디어만 받을지 이어지는 글·댓글까지 전부 받을지 고르게 한다.
///
/// 작성자 스레드와 댓글을 구역으로 나누고, 글마다 두 줄과 썸네일 하나만 보여 준다.
class ThreadTree extends StatelessWidget {
  const ThreadTree({super.key, required this.thread, required this.onDownload});

  final ThreadsThread thread;

  /// 고른 글들의 미디어를 다운로드 큐에 넣는다.
  final void Function(List<IgPost> posts) onDownload;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final authorNodes = [
      for (final node in thread.nodes)
        if (node.isByAuthor) node,
    ];
    final replyNodes = [
      for (final node in thread.nodes)
        if (!node.isByAuthor) node,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choices(context),
        const SizedBox(height: 16),
        _SectionHeader(
          post: thread.root,
          label: s.authorThreadSection(authorNodes.length),
        ),
        _section([
          for (final (index, node) in authorNodes.indexed)
            _ThreadRow(
              node: node,
              // 본문은 아이콘, 이어지는 글은 1부터 번호를 붙인다.
              number: index == 0 ? null : index,
              onDownload: _downloadOne(node),
            ),
        ]),
        if (replyNodes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionHeader(label: s.repliesSection(replyNodes.length)),
          _section([
            for (final node in replyNodes)
              _ThreadRow(node: node, onDownload: _downloadOne(node)),
          ]),
        ],
        if (thread.hasMoreReplies)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              s.moreRepliesHidden,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  VoidCallback? _downloadOne(ThreadNode node) =>
      node.post.hasDownloadableAssets ? () => onDownload([node.post]) : null;

  Widget _section(List<Widget> rows) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const Divider(height: 1, indent: 52),
          row,
        ],
      ],
    ),
  );

  Widget _choices(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final main = thread.mainPosts;
    final all = thread.allPosts;
    final mainFiles = ThreadsThread.fileCount(main);
    final allFiles = ThreadsThread.fileCount(all);

    if (allFiles == 0) {
      return Text(
        s.noThreadMedia,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: mainFiles == 0 ? null : () => onDownload(main),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(s.downloadMainMedia(mainFiles)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => onDownload(all),
            icon: const Icon(Icons.download, size: 18),
            label: Text(s.downloadAllMedia(allFiles)),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.post});

  final String label;

  /// 작성자 구역이면 작성자를 한 번만 보여 준다.
  final IgPost? post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = post;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          if (author != null) ...[
            _Avatar(post: author, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '@${author.authorName}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text('  ·  ', style: muted),
          ],
          Text(label, style: muted),
        ],
      ),
    );
  }
}

/// 글 하나를 두 줄로 줄여 보여 주는 행. 오른쪽에 첫 미디어 썸네일과 받기 버튼.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.node, required this.onDownload, this.number});

  final ThreadNode node;
  final VoidCallback? onDownload;

  /// 작성자 스레드의 순번. null 이면 본문(또는 댓글)이다.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final post = node.post;
    final isReply = node.role == ThreadRole.reply;
    // 두 줄 안에 최대한 담도록 줄바꿈을 공백으로 접는다.
    final caption = post.caption?.replaceAll(RegExp(r'\s*\n\s*'), ' ');

    final Widget leading;
    if (isReply) {
      leading = _Avatar(post: post, size: 24);
    } else if (number == null) {
      leading = Icon(
        Icons.push_pin_outlined,
        size: 18,
        color: theme.colorScheme.primary,
      );
    } else {
      leading = Text(
        '$number',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Padding(
      // 댓글의 답글은 한 단계 들여쓴다.
      padding: EdgeInsets.fromLTRB(node.depth > 1 ? 36 : 12, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isReply)
                  Text(
                    '@${post.authorName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  caption ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (post.hasDownloadableAssets) ...[
            const SizedBox(width: 10),
            _Thumb(post: post),
            IconButton(
              tooltip: s.downloadThisPost,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.download_outlined, size: 20),
              onPressed: onDownload,
            ),
          ] else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.post, required this.size});

  final IgPost post;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: NetworkThumb(
        url: post.user?.profilePicUrl,
        icon: Icons.person_outline,
      ),
    ),
  );
}

/// 첫 미디어 썸네일. 동영상 표시와, 여러 장이면 개수를 얹는다.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.post});

  final IgPost post;

  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    final items = post.items.where((item) => item.hasAssets).toList();
    final first = items.first;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkThumb(
              url: first.thumbnailUrl ?? first.best?.url,
              icon: first.isVideo ? Icons.movie_outlined : Icons.image_outlined,
            ),
            if (first.isVideo || items.length > 1)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: items.length > 1
                      ? Text(
                          '${items.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        )
                      : const Icon(
                          Icons.play_arrow,
                          size: 12,
                          color: Colors.white,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
