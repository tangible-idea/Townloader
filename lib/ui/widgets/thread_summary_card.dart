import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/summary_client.dart';
import '../../l10n/strings.dart';
import '../../models/threads_thread.dart';
import '../../state/settings_controller.dart';

/// 스레드 맨 위에 두는 AI 요약 카드.
///
/// 처음에는 글을 외부 AI 로 보내도 되는지 동의를 받고, 동의한 뒤로는 열 때마다 바로
/// 요약한다. Claude 와 Poe 를 바꿔 가며 비교할 수 있다.
class ThreadSummaryCard extends StatefulWidget {
  const ThreadSummaryCard({super.key, required this.thread, this.client});

  final ThreadsThread thread;

  /// 테스트에서 주입한다. 없으면 빌드 설정의 프록시로 만든다.
  final SummaryClient? client;

  @override
  State<ThreadSummaryCard> createState() => _ThreadSummaryCardState();
}

class _ThreadSummaryCardState extends State<ThreadSummaryCard> {
  late final SummaryClient _client = widget.client ?? SummaryClient();
  SummaryProvider _provider = SummaryProvider.claude;

  /// 공급자별로 받은 요약. 다시 고르면 새로 부르지 않는다.
  final Map<SummaryProvider, String> _summaries = {};
  bool _loading = false;
  SummaryException? _error;

  /// 요청이 겹치면 마지막 것만 화면에 반영한다.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (context.read<SettingsController>().aiSummaryConsented) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(ThreadSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.thread, widget.thread)) {
      _summaries.clear();
      _error = null;
      if (context.read<SettingsController>().aiSummaryConsented) _load();
    }
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_summaries.containsKey(_provider)) {
      setState(() => _error = null);
      return;
    }
    final request = ++_request;
    final provider = _provider;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _client.summarize(
        widget.thread,
        provider: provider,
        isKo: S.of(context).isKo,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _summaries[provider] = summary;
        _loading = false;
      });
    } on SummaryException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _askConsentAndLoad() async {
    final s = S.of(context);
    final settings = context.read<SettingsController>();
    final agreed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(s.aiConsentTitle),
            content: Text(s.aiConsentBody(_provider.label)),
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
    if (mounted) _load();
  }

  void _switchProvider(SummaryProvider provider) {
    if (provider == _provider) return;
    setState(() => _provider = provider);
    if (context.read<SettingsController>().aiSummaryConsented) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final consented = context.watch<SettingsController>().aiSummaryConsented;
    final summary = _summaries[_provider];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.summaryTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                SegmentedButton<SummaryProvider>(
                  segments: const [
                    ButtonSegment(
                      value: SummaryProvider.claude,
                      label: Text('Claude'),
                    ),
                    ButtonSegment(
                      value: SummaryProvider.poe,
                      label: Text('Poe'),
                    ),
                  ],
                  selected: {_provider},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged:
                      (selection) => _switchProvider(selection.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!consented)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _askConsentAndLoad,
                icon: const Icon(Icons.auto_awesome),
                label: Text(s.summaryShow),
              )
            else if (_loading && summary == null)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(s.summaryLoading, style: muted),
                ],
              )
            else if (summary != null) ...[
              SelectableText(summary, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Text(s.summaryNote, style: muted),
            ] else if (_error != null)
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
}
