import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../state/settings_controller.dart';

/// 처음 저장할 때 저작권과 개인 보관 용도를 알리고 동의를 받는다.
///
/// 한 번 동의하면 다시 묻지 않는다. 동의하지 않으면 false 라서 저장하지 않는다.
Future<bool> confirmPersonalUse(BuildContext context) async {
  final settings = context.read<SettingsController>();
  if (settings.personalUseAcknowledged) return true;

  final s = S.of(context);
  final agreed = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(s.personalUseTitle),
          content: Text(s.personalUseBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.personalUseAgree),
            ),
          ],
        ),
  );
  if (agreed != true) return false;

  await settings.acknowledgePersonalUse();
  return true;
}
