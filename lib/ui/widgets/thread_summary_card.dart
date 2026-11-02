import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/summary_client.dart';
import '../../l10n/strings.dart';
import '../../models/threads_thread.dart';
import '../../state/settings_controller.dart';
import 'shimmer.dart';

/// 스레드 맨 위에 두는 AI 요약 카드. 본문 요약(5줄 이하) 아래에 댓글 요점을 블릿으로
/// 함께 보여 준다. 받아 오면 줄마다 차례로 떠오른다.
///
/// 처음에는 글을 외부 AI 로 보내도 되는지 동의를 받고, 동의한 뒤로는 열 때마다 바로
/// 요약한다. 어느 모델이 요약할지는 A/B 테스트로 서버가 정하고, 평가가 모델 이름에
/// 끌리지 않도록 화면에는 보여 주지 않는다.
class ThreadSummaryCard extends StatefulWidget {
  const ThreadSummaryCard({super.key, required this.thread, this.client});

  final ThreadsThread thread;

  /// 테스트에서 주입한다. 없으면 빌드 설정의 프록시로 만든다.
  final SummaryClient? client;

  @override
  State<ThreadSummaryCard> createState() => _ThreadSummaryCardState();
}

class _ThreadSummaryCardState extends State<ThreadSummaryCard>
    with SingleTickerProviderStateMixin {
  late final SummaryClient _client = widget.client ?? SummaryClient();

  /// 요약이 도착하면 처음부터 다시 돌려 줄마다 차례로 보인다.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  ThreadDigest? _digest;
  bool _loading = false;
  bool _requested = false;
  SummaryException? _error;

  /// 평가를 보내는 동안 true. 그동안은 [_pendingVote] 를 먼저 보여 준다.
  bool _voting = false;
  SummaryVote? _pendingVote;

  /// 요청이 겹치면 마지막 것만 화면에 반영한다.
  int _request = 0;

  bool get _consented => context.read<SettingsController>().aiSummaryConsented;

  @override
  void initState() {
    super.initState();
    if (_consented) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(ThreadSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.thread, widget.thread)) {
      _digest = null;
      _error = null;
      _reveal.reset();
      if (_requested && _consented) _load();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final digest = await _client.summarize(
        widget.thread,
        isKo: S.of(context).isKo,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _digest = digest;
        _loading = false;
      });
      _reveal.forward(from: 0);
    } on SummaryException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 요약 보기 버튼. 아직 동의하지 않았으면 먼저 묻는다.
  Future<void> _start() async {
    if (!_consented) {
      final s = S.of(context);
      final settings = context.read<SettingsController>();
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.aiConsentTitle),
          content: Text(s.aiConsentBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.aiConsentAgree),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
      await settings.consentToAiSummary();
      if (!mounted) return;
    }
    setState(() => _requested = true);
    await _load();
  }

  /// 기기에 남기는 평가의 키. 공급자별로 따로 둔다.
  String _voteKey(ThreadDigest digest) =>
      '${digest.provider}:${SummaryClient.threadId(widget.thread)}';

  static String _newVoteId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 같은 쪽을 다시 누르면 평가를 취소한다. 실패하면 이전 표시로 돌아간다.
  Future<void> _vote(ThreadDigest digest, SummaryVote tapped) async {
    if (_voting) return;
    final s = S.of(context);
    final settings = context.read<SettingsController>();
    final key = _voteKey(digest);
    final previous = settings.summaryVote(key);
    final next = previous?.vote == tapped ? null : tapped;
    final voteId = previous?.voteId ?? _newVoteId();
    setState(() {
      _voting = true;
      _pendingVote = next;
    });
    try {
      await _client.sendFeedback(
        widget.thread,
        digest: digest,
        isKo: s.isKo,
        voteId: voteId,
        vote: next,
      );
      await settings.setSummaryVote(key, vote: next, voteId: voteId);
    } on SummaryException {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(s.summaryVoteFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _voting = false);
  }

  Widget _voteRow(ThreadDigest digest) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final stored = context.watch<SettingsController>().summaryVote(
      _voteKey(digest),
    );
    final vote = _voting ? _pendingVote : stored?.vote;

    Widget button(SummaryVote value, IconData on, IconData off, String label) {
      final selected = vote == value;
      return IconButton(
        tooltip: label,
        visualDensity: VisualDensity.compact,
        isSelected: selected,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        onPressed: () => _vote(digest, value),
        icon: Icon(selected ? on : off, size: 20),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        button(
          SummaryVote.up,
          Icons.thumb_up,
          Icons.thumb_up_outlined,
          s.summaryVoteUp,
        ),
        button(
          SummaryVote.down,
          Icons.thumb_down,
          Icons.thumb_down_outlined,
          s.summaryVoteDown,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final consented = context.watch<SettingsController>().aiSummaryConsented;
    final digest = _digest;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(s.summaryTitle, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (!consented || !_requested)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _start,
                icon: const Icon(Icons.auto_awesome),
                label: Text(s.summaryShow),
              )
            else if (_loading && digest == null)
              const _SummarySkeleton()
            else if (digest != null)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.topCenter,
                child: _body(context, digest, muted),
              )
            else if (_error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!.rateLimited
                          ? s.summaryRateLimited
                          : s.summaryFailed,
                      style: muted,
                    ),
                  ),
                  if (!_error!.rateLimited)
                    TextButton(onPressed: _load, child: Text(s.summaryRetry)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ThreadDigest digest, TextStyle? muted) {
    final s = S.of(context);
    final theme = Theme.of(context);
    // 본문 줄, 댓글 머리글, 댓글 요점, 안내, 평가 순서로 차례로 떠오른다.
    final count =
        digest.summary.length +
        (digest.comments.isEmpty ? 0 : 1 + digest.comments.length) +
        2;
    var index = 0;
    Widget reveal(Widget child) =>
        _Reveal(animation: _reveal, index: index++, count: count, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in digest.summary)
          reveal(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                line,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ),
          ),
        if (digest.comments.isNotEmpty) ...[
          reveal(
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.commentSummaryTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final point in digest.comments)
            reveal(
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        point,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        reveal(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.thread.hasMoreReplies && digest.comments.isNotEmpty
                  ? '${s.commentSummaryPartial} ${s.summaryNote}'
                  : s.summaryNote,
              style: muted,
            ),
          ),
        ),
        reveal(_voteRow(digest)),
      ],
    );
  }
}

/// [index] 번째 줄을 앞 줄보다 조금 늦게, 아래에서 살짝 떠오르며 보이게 한다.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = count <= 1 ? 0.0 : 0.6 * index / (count - 1);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// 요약을 만드는 동안 보이는 쉬머 줄.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          child: SizedBox(height: 14, child: ShimmerBox()),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [bar(0.95), bar(0.85), bar(0.9), bar(0.6)],
    );
  }
}
