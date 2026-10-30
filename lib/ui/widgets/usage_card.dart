import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/usage_meter.dart';

/// 바깥 서비스(Jev·Claude·Poe·카카오·Mapbox)를 부른 횟수를 토큰으로 바꿔 보여 준다.
/// 계산식은 [usageServices] 에 있다.
class UsageCard extends StatelessWidget {
  const UsageCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final meter = UsageMeter.instance;

    return ListenableBuilder(
      listenable: meter,
      builder: (context, _) {
        final since = meter.since;
        final used = [
          for (final service in usageServices)
            if (meter.countOf(service) > 0) service,
        ];
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.usageTokens(_grouped(meter.totalTokens)),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (since != null)
                            Text(
                              s.usageSince(
                                '${since.year}.${since.month}.${since.day}',
                              ),
                              style: muted,
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: meter.totalTokens == 0 ? null : meter.reset,
                      child: Text(s.usageReset),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (used.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(s.usageEmpty, style: muted),
                  )
                else
                  for (final service in used)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.isKo ? service.ko : service.en,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            s.usageRow(meter.countOf(service), service.weight),
                            style: muted,
                          ),
                          SizedBox(
                            width: 72,
                            child: Text(
                              _grouped(meter.tokensOf(service)),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(s.usageFormula, style: muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 12345 → "12,345".
  static String _grouped(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}
