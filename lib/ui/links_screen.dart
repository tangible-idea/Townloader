import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/maps_client.dart';
import '../l10n/strings.dart';
import '../models/saved_link.dart';
import '../services/download_service.dart';
import '../state/account_controller.dart';
import '../state/links_controller.dart';
import 'downloads_screen.dart';
import 'places_map_screen.dart';
import 'widgets/network_thumb.dart';
import 'widgets/state_views.dart';

/// 링크를 붙여넣어 카테고리별로 모으고, 글마다 찾은 장소를 보여 준다.
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key});

  @override
  State<LinksScreen> createState() => LinksScreenState();
}

class LinksScreenState extends State<LinksScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _input.text = text;
    setState(() {});
    await _save();
  }

  /// 공유 시트로 들어온 링크를 바로 저장한다. 이 탭이 받지 않는 링크(Threads 등)면
  /// false 를 돌려주고, 호출한 쪽이 읽기 탭으로 넘긴다.
  Future<bool> handleSharedLink(String link) async {
    final links = context.read<LinksController>();
    if (links.selectedCategory == null ||
        !LinksController.hasSavableLink(link)) {
      return false;
    }
    _input.text = link;
    setState(() {});
    await _save();
    return true;
  }

  Future<AddLinksResult> _save() async {
    final s = S.of(context);
    final links = context.read<LinksController>();
    final category = links.selectedCategory ?? '';
    final result = await links.addFromText(_input.text, isKo: s.isKo);
    if (!mounted) return result;
    FocusScope.of(context).unfocus();

    final skipped = s.linksSkipped(result.duplicates, result.unsupported);
    final message = result.added > 0
        ? [
            s.linksSaved(result.added, category),
            if (skipped.isNotEmpty) skipped,
          ].join(' · ')
        : (skipped.isNotEmpty ? skipped : s.linksNoneFound);
    if (result.added > 0) {
      _input.clear();
      setState(() {});
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    return result;
  }

  /// 카테고리 지도를 공유한다. 처음이면 public 으로 바뀐다는 것을 알리고 동의를 받는다.
  Future<void> _shareMap(BuildContext context, String category) async {
    final s = S.of(context);
    final account = context.read<AccountController>();
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    void show(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

    if (!account.isSignedIn) {
      show(s.shareMapNeedsSignIn);
      return;
    }

    final existing = account.shareOf(category);
    if (existing != null) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.public),
                title: Text('$category · ${s.sharePublicLabel}'),
                subtitle: Text(existing.url),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: Text(s.shareLinkAgain),
                onTap: () => Navigator.of(context).pop('send'),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(s.shareStop),
                onTap: () => Navigator.of(context).pop('stop'),
              ),
            ],
          ),
        ),
      );
      try {
        if (action == 'send') {
          await _sendShareLink(existing, origin);
        } else if (action == 'stop') {
          await account.unshare(category);
          show(s.shareStopped);
        }
      } on MapsException catch (error) {
        show(error.message);
      }
      return;
    }

    if (!context.mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.shareMapTitle(category)),
        content: Text(s.shareMapBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.shareMapAction),
          ),
        ],
      ),
    );
    if (agreed != true) return;
    try {
      final share = await account.share(category);
      await _sendShareLink(share, origin);
    } on MapsException catch (error) {
      show(error.message);
    }
  }

  Future<void> _sendShareLink(MapShare share, Rect? origin) =>
      SharePlus.instance.share(
        ShareParams(
          uri: Uri.parse(share.url),
          subject: share.category,
          sharePositionOrigin: origin,
        ),
      );

  Future<void> _newCategory() async {
    final s = S.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.linksNewCategory),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: s.linksCategoryHint),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(s.linksAdd),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && mounted) {
      await context.read<LinksController>().addCategory(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final controller = context.watch<LinksController>();
    final activeDownloads = context.select<DownloadService, int>(
      (service) => service.activeCount,
    );
    final links = controller.links;
    // 지도는 지금 고른 카테고리의 장소만 보여 준다.
    final hasPlaces = links.any((link) => link.places.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.linksTitle),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: s.shareMap,
              icon: const Icon(Icons.ios_share),
              onPressed: controller.selectedCategory == null
                  ? null
                  : () => _shareMap(context, controller.selectedCategory!),
            ),
          ),
          IconButton(
            tooltip: s.mapOpen,
            icon: const Icon(Icons.public),
            onPressed: hasPlaces
                ? () => PlacesMapScreen.open(
                    context,
                    category: controller.selectedCategory,
                  )
                : null,
          ),
          IconButton(
            tooltip: s.downloadHistory,
            icon: Badge.count(
              count: activeDownloads,
              isLabelVisible: activeDownloads > 0,
              child: const Icon(Icons.download_outlined),
            ),
            onPressed: () => DownloadsScreen.open(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _categories(context, controller)),
                SliverToBoxAdapter(child: _pasteBox(context)),
                if (!controller.isLoaded)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (links.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MessageView(
                      icon: Icons.bookmarks_outlined,
                      title: s.linksEmptyTitle,
                      description: s.linksEmptyDesc,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: links.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _LinkCard(link: links[index]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categories(BuildContext context, LinksController controller) {
    final s = S.of(context);
    final shared = {
      for (final share
          in context.watch<AccountController?>()?.shares ?? const [])
        share.category,
    };
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final category in controller.categories) ...[
            ChoiceChip(
              // 공유해서 public 이 된 카테고리는 지구 아이콘으로 알린다.
              avatar: shared.contains(category)
                  ? const Icon(Icons.public, size: 16)
                  : null,
              label: Text('$category ${controller.countIn(category)}'),
              selected: category == controller.selectedCategory,
              onSelected: (_) => controller.selectCategory(category),
            ),
            const SizedBox(width: 8),
          ],
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(s.linksNewCategory),
            onPressed: _newCategory,
          ),
        ],
      ),
    );
  }

  Widget _pasteBox(BuildContext context) {
    final s = S.of(context);
    final hasText = _input.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.linksHint,
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  tooltip: s.paste,
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: hasText ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
            child: Text(s.linksSave),
          ),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final SavedLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final canOpenMap =
        link.status == LinkStatus.ready && link.places.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpenMap
            ? () => PlacesMapScreen.open(context, link: link)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 64,
                      height: 80,
                      child: NetworkThumb(url: link.coverUrl),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 대표 제목이 아직 없으면(분석 중) 계정명을 제목 자리에 둔다.
                        Text(
                          link.title ??
                              (link.author == null
                                  ? link.code
                                  : '@${link.author}'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (link.caption != null ||
                            (link.title != null && link.author != null)) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (link.title != null && link.author != null)
                                '@${link.author}',
                              if (link.caption != null)
                                link.caption!.replaceAll('\n', ' '),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _status(context),
                      ],
                    ),
                  ),
                  _menu(context),
                ],
              ),
              if (link.places.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final place in link.places)
                      _PlaceChip(
                        place: place,
                        onTap: canOpenMap
                            ? () => PlacesMapScreen.open(
                                context,
                                link: link,
                                place: place,
                              )
                            : null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return switch (link.status) {
      LinkStatus.analyzing => Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(s.linksAnalyzing, style: muted),
        ],
      ),
      LinkStatus.ready => Text(
        link.places.isEmpty
            ? s.linksNoPlaces
            : s.linksPlaceCount(link.places.length),
        style: link.places.isEmpty
            ? muted
            : theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
      ),
      LinkStatus.failed => Row(
        children: [
          Flexible(
            child: Text(
              link.error ?? s.failedToLoad,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => context.read<LinksController>().retry(link),
            child: Text(s.linksRetry),
          ),
        ],
      ),
    };
  }

  Widget _menu(BuildContext context) {
    final s = S.of(context);
    final controller = context.read<LinksController>();
    final others = [
      for (final category in controller.categories)
        if (category != link.category) category,
    ];
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case '_open':
            launchUrl(
              Uri.parse(link.url),
              mode: LaunchMode.externalApplication,
            );
          case '_retry':
            controller.retry(link);
          case '_delete':
            controller.remove(link);
          default:
            controller.moveTo(link, value);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: '_open', child: Text(s.openOriginal)),
        if (link.status != LinkStatus.analyzing)
          PopupMenuItem(value: '_retry', child: Text(s.linksRetry)),
        for (final category in others)
          PopupMenuItem(
            value: category,
            child: Text('${s.linksMove}: $category'),
          ),
        PopupMenuItem(value: '_delete', child: Text(s.linksDelete)),
      ],
    );
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.place, this.onTap});

  final SavedPlace place;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final icon = switch (place.source) {
      PlaceSource.tag => Icons.place,
      PlaceSource.image => Icons.image_outlined,
      PlaceSource.caption => Icons.notes,
    };
    return Tooltip(
      message: [
        place.address ?? '',
        if (place.approximate) s.linksApproximate,
      ].where((text) => text.isNotEmpty).join(' · '),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  place.approximate ? '${place.name} ~' : place.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
