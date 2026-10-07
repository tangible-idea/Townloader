import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/poe_tts_client.dart';

import '../../l10n/strings.dart';
import '../../models/ig_post.dart';
import '../../models/threads_thread.dart';
import '../../services/comment_reader.dart';
import 'network_thumb.dart';
import 'peek_preview.dart';
import 'post_card.dart';

/// Threads 스레드를 한눈에 훑어볼 수 있게 촘촘한 목록으로 보여 주고,
/// 체크한 글들의 미디어를 받게 한다.
///
/// 작성자 스레드와 댓글을 구역으로 나누고, 글마다 두 줄과 썸네일 하나만 보여 준다.
/// 미디어가 있는 글은 처음에 모두 체크되어 있다.
class ThreadTree extends StatefulWidget {
  const ThreadTree({
    super.key,
    required this.thread,
    required this.onDownload,
    this.commentReader,
  });

  final ThreadsThread thread;

  /// 고른 글들의 미디어를 다운로드 큐에 넣는다.
  final void Function(List<IgPost> posts) onDownload;

  /// 댓글 읽어 주기. 없으면 빌드에 Poe 키가 있을 때만 만들어 쓴다(테스트에서 주입).
  final CommentReader? commentReader;

  @override
  State<ThreadTree> createState() => _ThreadTreeState();
}

class _ThreadTreeState extends State<ThreadTree> {
  /// 체크된 글. 같은 글이 두 번 나오지 않으므로 [ThreadNode] 로 구분한다.
  late Set<ThreadNode> _selected = _allSelectable();

  CommentReader? _reader;
  bool _ownsReader = false;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    _reader = widget.commentReader;
    if (_reader == null && AppConfig.hasPoeKey) {
      _reader = CommentReader(
        synthesize: PoeTtsClient(apiKey: AppConfig.poeApiKey).synthesize,
      );
      _ownsReader = true;
    }
    _reader?.addListener(_onReaderChanged);
  }

  @override
  void dispose() {
    _reader?.removeListener(_onReaderChanged);
    if (_ownsReader) {
      _reader?.dispose();
    } else {
      _reader?.stop();
    }
    super.dispose();
  }

  void _onReaderChanged() {
    if (!mounted) return;
    final error = _reader?.error;
    if (error != null && error != _shownError) {
      _shownError = error;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
        );
    }
    setState(() {});
  }

  List<ThreadNode> get _replyNodes => [
    for (final node in widget.thread.nodes)
      if (!node.isByAuthor) node,
  ];

  /// 읽어 줄 글. 줄바꿈은 쉼으로 바꾸고 링크는 읽지 않는다.
  static String _speakable(IgPost post) => (post.caption ?? '')
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'\s*\n\s*'), '. ')
      .trim();

  void _toggleReading() {
    final reader = _reader;
    if (reader == null) return;
    if (reader.isActive) {
      reader.stop();
    } else {
      _shownError = null;
      reader.start([for (final node in _replyNodes) _speakable(node.post)]);
    }
  }

  Widget _repliesHeader(BuildContext context, int count) {
    final s = S.of(context);
    final reader = _reader;
    final header = _SectionHeader(label: s.repliesSection(count));
    if (reader == null) return header;

    return Row(
      children: [
        Expanded(child: header),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(
            onPressed: _toggleReading,
            icon: reader.isActive
                ? (reader.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle_outlined, size: 18))
                : const Icon(Icons.record_voice_over_outlined, size: 18),
            label: Text(reader.isActive ? s.stopReading : s.readReplies),
          ),
        ),
      ],
    );
  }

  ThreadsThread get thread => widget.thread;

  /// 작성자가 이어 단 글이 없으면 본문을 카드로 크게 보여 준다. 카드에 받기 버튼이
  /// 따로 있으므로 체크 대상에서는 뺀다.
  bool get _singleAuthorPost => widget.thread.authorPostCount == 1;

  Set<ThreadNode> _allSelectable() => {
    for (final node in widget.thread.nodes)
      if (node.post.hasDownloadableAssets &&
          !(_singleAuthorPost && node.role == ThreadRole.root))
        node,
  };

  @override
  void didUpdateWidget(ThreadTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 링크를 열었으면 선택을 처음 상태로 되돌린다.
    if (!identical(oldWidget.thread, widget.thread)) {
      _selected = _allSelectable();
    }
  }

  void _toggle(ThreadNode node) => setState(() {
    if (!_selected.remove(node)) _selected.add(node);
  });

  /// 화면 순서대로 체크된 글.
  List<IgPost> get _selectedPosts => [
    for (final node in thread.nodes)
      if (_selected.contains(node)) node.post,
  ];

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

    final readingIndex = _reader?.current;
    final reading = readingIndex == null || readingIndex >= replyNodes.length
        ? null
        : replyNodes[readingIndex];

    _ThreadRow row(ThreadNode node) => _ThreadRow(
      node: node,
      highlighted: identical(node, reading),
      selected: _selected.contains(node),
      onToggle: node.post.hasDownloadableAssets ? () => _toggle(node) : null,
    );

    if (_singleAuthorPost) {
      // 글이 하나뿐이면 목록 대신 카드로 크게, 동영상도 그 자리에서 재생한다.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PostCard(post: thread.root),
          if (replyNodes.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (_allSelectable().isNotEmpty) ...[
              _choices(context),
              const SizedBox(height: 16),
            ],
            _repliesHeader(context, replyNodes.length),
            _section([for (final node in replyNodes) row(node)]),
          ],
          if (thread.hasMoreReplies) _moreRepliesNote(context),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choices(context),
        const SizedBox(height: 16),
        _SectionHeader(
          post: thread.root,
          label: s.authorThreadSection(authorNodes.length),
        ),
        _section([for (final node in authorNodes) row(node)]),
        if (replyNodes.isNotEmpty) ...[
          const SizedBox(height: 16),
          _repliesHeader(context, replyNodes.length),
          _section([for (final node in replyNodes) row(node)]),
        ],
        if (thread.hasMoreReplies) _moreRepliesNote(context),
      ],
    );
  }

  Widget _moreRepliesNote(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Text(
      S.of(context).moreRepliesHidden,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

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
    final selectable = _allSelectable();

    if (selectable.isEmpty) {
      return Text(
        s.noThreadMedia,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final main = thread.mainPosts;
    final mainFiles = ThreadsThread.fileCount(main);
    final picked = _selectedPosts;
    final pickedFiles = ThreadsThread.fileCount(picked);
    final allChecked = _selected.length == selectable.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 전체 선택/해제. 일부만 체크되면 가운데 상태로 보인다.
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selected = allChecked ? {} : selectable),
          child: Row(
            children: [
              Checkbox(
                tristate: true,
                value: allChecked ? true : (_selected.isEmpty ? false : null),
                onChanged: (_) =>
                    setState(() => _selected = allChecked ? {} : selectable),
              ),
              Text(
                s.selectedPosts(_selected.length, selectable.length),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (!_singleAuthorPost) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: mainFiles == 0
                      ? null
                      : () => widget.onDownload(main),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(s.downloadMainMedia(mainFiles)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: picked.isEmpty
                    ? null
                    : () => widget.onDownload(picked),
                icon: const Icon(Icons.download, size: 18),
                label: Text(s.downloadSelected(pickedFiles)),
              ),
            ),
          ],
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

/// 글 하나를 두 줄로 줄여 보여 주는 행. 왼쪽에 받을지 고르는 체크박스, 오른쪽에
/// 첫 미디어 썸네일. 행을 눌러도 체크가 바뀐다.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.node,
    required this.selected,
    this.highlighted = false,
    required this.onToggle,
  });

  final ThreadNode node;
  final bool selected;

  /// 지금 소리 내어 읽고 있는 댓글인지.
  final bool highlighted;

  /// 미디어가 없는 글은 고를 수 없어 null 이다.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = node.post;
    final isReply = node.role == ThreadRole.reply;
    // 두 줄 안에 최대한 담도록 줄바꿈을 공백으로 접는다.
    final caption = post.caption?.replaceAll(RegExp(r'\s*\n\s*'), ' ');

    final Widget leading;
    if (onToggle != null) {
      leading = Checkbox(
        value: selected,
        onChanged: (_) => onToggle!(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    } else if (node.role == ThreadRole.root) {
      // 미디어 없는 본문은 고를 게 없으니 본문 표시만 남긴다.
      leading = Icon(
        Icons.push_pin_outlined,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      );
    } else {
      leading = const SizedBox.shrink();
    }

    // 길게 누르는 동안 미디어를 크게 띄운다(동영상은 바로 재생).
    return PeekOnLongPress(
      post: post,
      child: Material(
        // 읽고 있는 댓글은 배경을 칠해 어디를 읽는지 보이게 한다.
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            // 댓글의 답글은 한 단계 들여쓴다.
            padding: EdgeInsets.fromLTRB(node.depth > 1 ? 32 : 8, 8, 12, 8),
            child: Row(
              children: [
                SizedBox(width: 36, child: Center(child: leading)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isReply)
                        Row(
                          children: [
                            _Avatar(post: post, size: 16),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '@${post.authorName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
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
                ],
              ],
            ),
          ),
        ),
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
