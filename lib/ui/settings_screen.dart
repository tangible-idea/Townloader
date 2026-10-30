import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/file_saver.dart';
import '../services/settings_store.dart';
import '../state/settings_controller.dart';
import 'widgets/account_card.dart';
import 'widgets/usage_card.dart';

/// 다운로드 동작을 설정하는 화면.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(s.settingsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle(context, s.accountSection),
                const AccountCard(),
                const SizedBox(height: 16),
                _sectionTitle(context, s.languageSection),
                Card(
                  child: RadioGroup<String?>(
                    groupValue: settings.languageCode,
                    onChanged: settings.setLanguage,
                    child: Column(
                      children: [
                        RadioListTile<String?>(
                          value: null,
                          title: Text(s.languageSystem),
                        ),
                        RadioListTile<String?>(
                          value: 'ko',
                          title: Text(s.languageKorean),
                        ),
                        RadioListTile<String?>(
                          value: 'en',
                          title: Text(s.languageEnglish),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, s.qualitySection),
                Card(
                  child: Column(
                    children: [
                      RadioGroup<QualityPreference>(
                        groupValue: settings.quality,
                        onChanged: (value) {
                          if (value != null) settings.setQuality(value);
                        },
                        child: Column(
                          children: [
                            for (final option in QualityPreference.values)
                              RadioListTile<QualityPreference>(
                                value: option,
                                title: Text(
                                  option == QualityPreference.best
                                      ? s.qualityBest
                                      : s.qualitySmall,
                                ),
                                subtitle: Text(
                                  option == QualityPreference.best
                                      ? s.qualityBestSub
                                      : s.qualitySmallSub,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!MediaFileSaver.isDesktop) ...[
                        const Divider(height: 1),
                        SwitchListTile(
                          value: settings.saveToGallery,
                          onChanged: settings.setSaveToGallery,
                          title: Text(s.saveToPhotos),
                          subtitle: Text(s.saveToPhotosSub),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(s.storageSection),
                    subtitle: Text(
                      MediaFileSaver.isDesktop
                          ? 'Townloader/<account>/'
                          : settings.saveToGallery
                          ? (s.isKo
                                ? '사진 앱: Townloader 앨범'
                                : 'Photos: Townloader album')
                          : (s.isKo
                                ? '앱 문서 폴더: Townloader'
                                : 'App documents: Townloader'),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _sectionTitle(context, s.usageSection),
                const UsageCard(),
                const SizedBox(height: 16),
                _sectionTitle(context, s.infoSection),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      s.infoDesc,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
