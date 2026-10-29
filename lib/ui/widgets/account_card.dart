import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/social_sign_in.dart';
import '../../state/account_controller.dart';

/// 설정 화면의 계정 칸. 로그인하면 Links 가 서버에 동기화되고 지도를 공유할 수 있다.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final account = context.watch<AccountController>();
    final signIn = context.read<SocialSignIn>();
    final session = account.session;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final error = account.error;

    if (session == null) {
      final providers = [
        if (signIn.googleAvailable)
          FilledButton.icon(
            onPressed:
                account.busy
                    ? null
                    : () => account.signIn('google', signIn.google),
            icon: const Icon(Icons.login),
            label: Text(s.signInGoogle),
          ),
        if (signIn.appleAvailable)
          FilledButton.tonalIcon(
            onPressed:
                account.busy
                    ? null
                    : () => account.signIn('apple', signIn.apple),
            icon: const Icon(Icons.apple),
            label: Text(s.signInApple),
          ),
      ];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.accountSignedOutDesc, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              if (providers.isEmpty)
                Text(s.signInUnavailable, style: muted)
              else
                for (final button in providers) ...[
                  button,
                  const SizedBox(height: 8),
                ],
              if (account.busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error,
                  style: muted?.copyWith(color: theme.colorScheme.error),
                ),
            ],
          ),
        ),
      );
    }

    final who =
        session.email ?? (session.provider == 'apple' ? 'Apple' : 'Google');
    final lastSynced = account.lastSynced;
    final status =
        account.syncing
            ? s.syncing
            : lastSynced == null
            ? null
            : s.syncedAt(
              MaterialLocalizations.of(
                context,
              ).formatTimeOfDay(TimeOfDay.fromDateTime(lastSynced)),
            );

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(s.signedInAs(who)),
            subtitle: status == null ? null : Text(status),
            trailing: IconButton(
              tooltip: s.syncNow,
              onPressed: account.syncing ? null : account.sync,
              icon: const Icon(Icons.sync),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                error,
                style: muted?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(s.signOut),
            subtitle: Text(s.signOutDesc),
            enabled: !account.busy,
            onTap: () async {
              await account.signOut();
              await signIn.signOut();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              s.deleteAccount,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            enabled: !account.busy,
            onTap: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = S.of(context);
    final account = context.read<AccountController>();
    final signIn = context.read<SocialSignIn>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(s.deleteAccountTitle),
            content: Text(s.deleteAccountBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.delete),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await account.deleteAccount();
      await signIn.signOut();
    } on Object {
      // 오류는 카드에 보인다.
    }
  }
}
