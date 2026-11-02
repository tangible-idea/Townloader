import 'dart:math' as math;

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
import '../state/resolve_controller.dart';
import 'downloads_screen.dart';
import 'places_map_screen.dart';
import 'widgets/drop_targets.dart';
import 'widgets/network_thumb.dart';
import 'widgets/place_category_icon.dart';
import 'widgets/shimmer.dart';
import 'widgets/state_views.dart';

/// 링크를 붙여넣어 카테고리별로 모으고, 글마다 찾은 장소를 보여 준다.
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key, this.onOpenRead});

  /// 링크를 읽기(Read) 탭으로 보내 바로 열 때 호출한다.
  final void Function(String link)? onOpenRead;

  @override
  State<LinksScreen> createState() => LinksScreenState();
}

class LinksScreenState extends State<LinksScreen>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();

  /// 카드를 길게 눌러 끌고 있는 링크. 끄는 동안 위에는 카테고리가 세로로 펼쳐지고
  /// 아래에는 쓰레기통이 나온다. 놓은 뒤 [_dragMode] 가 다 접힐 때까지 남아 있다.
  SavedLink? _dragging;
  late final AnimationController _dragMode = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 260),
  );

  /// 장소 목록을 펼친 링크. 카드가 화면 밖으로 나갔다 돌아와도 펼친 채로 두려고 여기서 들고 있다.
  final _expandedPlaces = <String>{};

  late final LinksController _linksController = context.read<LinksController>();

  @override
  void initState() {
    super.initState();
    _linksController.autoMoved.addListener(_showAutoMoved);
  }

  /// 보던 카테고리에서 글이 사라지므로 어디로 갔는지 알리고 되돌릴 수 있게 한다.
  void _showAutoMoved() {
    final moved = _linksController.autoMoved.value;
    if (moved == null || !mounted) return;
    final s = S.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s.linksMovedTo(moved.to)),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: s.undo,
            onPressed: () {
              for (final link in _linksController.allLinks) {
                if (link.code == moved.code) {
                  _linksController.moveTo(link, moved.from);
                  break;
                }
              }
            },
          ),
        ),
      );
  }

  @override
  void dispose() {
    _linksController.autoMoved.removeListener(_showAutoMoved);
    _dragMode.dispose();
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
    final message =
        result.added > 0
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

  /// 카테고리 또는 개별 글 지도를 공유한다. 처음이면 public 으로 바뀐다는 것을 알리고 동의를 받는다.
  Future<void> _shareMap(
    BuildContext context,
    String shareKey, {
    String? label,
    bool isPost = false,
  }) async {
    final s = S.of(context);
    final displayTitle = label ?? shareKey;
    final account = context.read<AccountController>();
    final messenger = ScaffoldMessenger.of(context);
    final postCode = isPost ? shareKey.substring('post:'.length) : null;
    final places = [
      for (final link in context.read<LinksController>().allLinks)
        if (postCode != null
            ? link.code == postCode
            : link.category == shareKey)
          for (final place in link.places) place.name,
    ];
    final isKo = s.isKo;
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    void show(String message) =>
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );

    if (!account.isSignedIn) {
      show(s.shareMapNeedsSignIn);
      return;
    }

    var existing = account.shareOf(shareKey);
    if (existing == null) {
      if (!context.mounted) return;
      final agreed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(s.shareMapTitle(displayTitle)),
              content: Text(isPost ? s.sharePostBody : s.shareMapBody),
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
        existing = await account.share(shareKey);
      } on MapsException catch (error) {
        show(error.message);
        return;
      }
    }
    final share = existing;
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text('$displayTitle · ${s.sharePublicLabel}'),
                  subtitle: Text(share.url),
                ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(s.copyLink),
                  onTap: () => Navigator.of(context).pop('copy'),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: Text(s.shareOpenInBrowser),
                  onTap: () => Navigator.of(context).pop('open'),
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
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: share.url));
        show(s.linkCopied);
      } else if (action == 'open') {
        await launchUrl(
          Uri.parse(share.browserUrl),
          mode: LaunchMode.externalApplication,
        );
      } else if (action == 'send') {
        await _sendShareLink(
          share,
          origin,
          subject: displayTitle,
          places: places,
          isKo: isKo,
        );
      } else if (action == 'stop') {
        await account.unshare(shareKey);
        show(s.shareStopped);
      }
    } on MapsException catch (error) {
      show(error.message);
    }
  }

  Future<void> _sendShareLink(
    MapShare share,
    Rect? origin, {
    required String subject,
    required List<String> places,
    required bool isKo,
  }) => SharePlus.instance.share(
    ShareParams(
      text: shareMessage(
        title: subject,
        places: places,
        url: share.url,
        isKo: isKo,
      ),
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );

  Future<void> _newCategory() async {
    final s = S.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
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
            builder:
                (context) => IconButton(
                  tooltip: s.shareMap,
                  icon: const Icon(Icons.ios_share),
                  onPressed:
                      controller.selectedCategory == null
                          ? null
                          : () =>
                              _shareMap(context, controller.selectedCategory!),
                ),
          ),
          IconButton(
            tooltip: s.mapOpen,
            icon: const Icon(Icons.public),
            onPressed:
                hasPlaces
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
            child: Stack(
              children: [
                _list(context, controller, links),
                if (_dragging != null) ..._dropTargets(context, controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    LinksController controller,
    List<SavedLink> links,
  ) {
    final s = S.of(context);
    return CustomScrollView(
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
              itemBuilder: (context, index) {
                final item = links[index];
                final card = _SwipeActionCard(
                  onRead: () => _openInRead(item.url),
                  onDelete: () => context.read<LinksController>().remove(item),
                  child: _LinkCard(
                    link: item,
                    placesExpanded: _expandedPlaces.contains(item.code),
                    onTogglePlaces:
                        () => setState(() {
                          if (!_expandedPlaces.remove(item.code)) {
                            _expandedPlaces.add(item.code);
                          }
                        }),
                    onRead: () => _openInRead(item.url),
                    onShare:
                        (buttonContext) => _shareMap(
                          buttonContext,
                          AccountController.postShareKey(item.code),
                          label:
                              item.title ??
                              (item.author == null
                                  ? item.code
                                  : '@${item.author}'),
                          isPost: true,
                        ),
                  ),
                );
                return _draggable(context, item, card);
              },
            ),
          ),
      ],
    );
  }

  /// 길게 누르면 카드를 끌 수 있다. 위의 카테고리에 놓으면 옮기고, 아래 쓰레기통에
  /// 놓으면 지운다.
  Widget _draggable(BuildContext context, SavedLink item, Widget card) {
    return LongPressDraggable<SavedLink>(
      key: ValueKey(item.code),
      data: item,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(link: item),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      onDragStarted: () {
        HapticFeedback.mediumImpact();
        setState(() => _dragging = item);
        _dragMode.forward();
      },
      onDragEnd: (_) => _endDrag(),
      child: card,
    );
  }

  /// 놓은 뒤 카테고리·쓰레기통을 원래대로 접는다.
  ///
  /// 옮기거나 지운 카드는 목록에서 빠지는데, 그러면 Flutter 가 끌기 끝 알림을 주지 않아서
  /// 놓은 곳에서도 직접 부른다. 두 번 불러도 한 번만 접힌다.
  Future<void> _endDrag() async {
    if (_dragging == null || _dragMode.status == AnimationStatus.reverse) {
      return;
    }
    await _dragMode.reverse();
    if (mounted) setState(() => _dragging = null);
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );

  List<Widget> _dropTargets(BuildContext context, LinksController controller) {
    final s = S.of(context);
    final link = _dragging!;
    return [
      // 나머지를 살짝 어둡게 해 놓을 곳에 눈이 가게 한다.
      Positioned.fill(
        child: IgnorePointer(
          child: FadeTransition(
            opacity: _dragMode,
            child: const ColoredBox(color: Color(0x33000000)),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: CategoryDropPanel<SavedLink>(
          animation: _dragMode,
          categories: controller.categories,
          current: link.category,
          hint: s.linksDropToMove,
          canAccept: (link, category) => link.category != category,
          onDrop: (link, category) {
            controller.moveTo(link, category);
            _toast(s.linksMovedTo(category));
            _endDrag();
          },
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        bottom: 20,
        child: TrashDropZone<SavedLink>(
          animation: _dragMode,
          label: s.linksDropToDelete,
          onDrop: (link) {
            controller.remove(link);
            _toast(s.linksDeleted);
            _endDrag();
          },
        ),
      ),
    ];
  }

  void _openInRead(String url) {
    final callback = widget.onOpenRead;
    if (callback != null) {
      callback(url);
    } else {
      context.read<ResolveController?>()?.resolve(url);
    }
  }

  Widget _categories(BuildContext context, LinksController controller) {
    final s = S.of(context);
    final shared = {
      for (final share
          in context.watch<AccountController?>()?.shares ?? const [])
        share.category,
    };
    // 카드를 끄는 동안에는 이 줄이 세로 목록([CategoryDropPanel])으로 바뀐다.
    return FadeTransition(
      opacity: ReverseAnimation(_dragMode),
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            for (final category in controller.categories) ...[
              ChoiceChip(
                // 공유해서 public 이 된 카테고리는 링크 아이콘으로 알린다.
                avatar:
                    shared.contains(category)
                        ? const Icon(Icons.link, size: 16)
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
  const _LinkCard({
    required this.link,
    required this.placesExpanded,
    required this.onTogglePlaces,
    required this.onShare,
    this.onRead,
  });

  final SavedLink link;
  final bool placesExpanded;
  final VoidCallback onTogglePlaces;
  final void Function(BuildContext buttonContext) onShare;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final share = context.watch<AccountController?>()?.shareOfPost(link.code);
    final isShared = share != null;

    final canOpenMap =
        link.status == LinkStatus.ready && link.places.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            canOpenMap ? () => PlacesMapScreen.open(context, link: link) : null,
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
                  const SizedBox(width: 4),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _menu(context, share: share),
                      const SizedBox(height: 4),
                      Builder(
                        builder:
                            (buttonContext) => IconButton(
                              tooltip: s.shareMap,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              icon: Icon(
                                isShared ? Icons.link : Icons.ios_share,
                                size: 20,
                                color:
                                    isShared ? theme.colorScheme.primary : null,
                              ),
                              onPressed: () => onShare(buttonContext),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              // 다시 찾을 때도 예전 칩 대신 뼈대를 보여 준다.
              if (link.status == LinkStatus.analyzing) ...[
                const SizedBox(height: 10),
                const PlaceChipsSkeleton(),
              ] else if (link.places.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PlaceChips(
                  link: link,
                  canOpenMap: canOpenMap,
                  expanded: placesExpanded,
                  onToggle: onTogglePlaces,
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
      LinkStatus.analyzing => Text(s.linksAnalyzing(link.code), style: muted),
      LinkStatus.ready => Text(
        link.places.isEmpty
            ? s.linksNoPlaces
            : s.linksPlaceCount(link.places.length),
        style:
            link.places.isEmpty
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

  Widget _menu(BuildContext context, {MapShare? share}) {
    final s = S.of(context);
    final controller = context.read<LinksController>();
    final others = [
      for (final category in controller.categories)
        if (category != link.category) category,
    ];
    return PopupMenuButton<String>(
      // `constraints` 는 펼친 메뉴의 크기라서 버튼 크기는 style 로 줄인다.
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        fixedSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case '_read':
            onRead?.call();
          case '_copy_shared':
            if (share != null) {
              Clipboard.setData(ClipboardData(text: share.url));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(s.linkCopied),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          case '_open_shared':
            if (share != null) {
              launchUrl(
                Uri.parse(share.browserUrl),
                mode: LaunchMode.externalApplication,
              );
            }
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
      itemBuilder:
          (context) => [
            if (onRead != null)
              PopupMenuItem(value: '_read', child: Text(s.navDownload)),
            if (share != null)
              PopupMenuItem(value: '_copy_shared', child: Text(s.copyLink)),
            if (share != null)
              PopupMenuItem(
                value: '_open_shared',
                child: Text(s.shareOpenInBrowser),
              ),
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

/// 장소가 많으면 카드가 너무 길어지므로 [_collapsedCount]곳까지만 보이고 나머지는 펼쳐서 본다.
class _PlaceChips extends StatelessWidget {
  const _PlaceChips({
    required this.link,
    required this.canOpenMap,
    required this.expanded,
    required this.onToggle,
  });

  static const _collapsedCount = 15;

  final SavedLink link;
  final bool canOpenMap;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final places = link.places;
    final hidden = places.length - _collapsedCount;
    final visible =
        expanded || hidden <= 0 ? places : places.take(_collapsedCount);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final place in visible)
          _PlaceChip(
            place: place,
            onTap:
                canOpenMap
                    ? () =>
                        PlacesMapScreen.open(context, link: link, place: place)
                    : null,
          ),
        if (hidden > 0)
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      expanded
                          ? s.linksShowLessPlaces
                          : s.linksShowMorePlaces(hidden),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    // 사진은 받지 않고 업종 아이콘으로 보여 준다. 업종을 모르면 장소를 찾은 곳의 아이콘.
    final icon =
        placeCategoryIcon(place.category) ??
        switch (place.source) {
          PlaceSource.tag => Icons.place_outlined,
          PlaceSource.image => Icons.image_outlined,
          PlaceSource.caption => Icons.notes,
        };
    return Tooltip(
      message: [
        place.category ?? '',
        place.address ?? '',
        place.phone ?? '',
        if (place.approximate) s.linksApproximate,
      ].where((text) => text.isNotEmpty).join(' · '),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 5),
                Text(
                  place.approximate ? '${place.name} ~' : place.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                if (place.category != null && place.category!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    place.category!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 카드를 가로로 밀면 Read(읽기 탭으로 보내기)와 Delete(항목 삭제) 버튼을 드러낸다.
class _SwipeActionCard extends StatefulWidget {
  const _SwipeActionCard({
    required this.onRead,
    required this.onDelete,
    required this.child,
  });

  final VoidCallback onRead;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<_SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<_SwipeActionCard> {
  static const double _revealWidth = 104;
  double _offset = 0;
  bool _dragging = false;

  void _onDragStart(DragStartDetails _) {
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_revealWidth, _revealWidth);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0;
    setState(() {
      _dragging = false;
      if (_offset > _revealWidth * 0.35 || (vx > 300 && _offset >= 0)) {
        _offset = _revealWidth;
      } else if (_offset < -_revealWidth * 0.35 ||
          (vx < -300 && _offset <= 0)) {
        _offset = -_revealWidth;
      } else {
        _offset = 0;
      }
    });
  }

  void _close() {
    if (_offset != 0) setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final alignLeft = _offset >= 0;

    final actions = SizedBox(
      width: _revealWidth - 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.chrome_reader_mode_outlined,
              label: s.navDownload,
              background: scheme.primary,
              foreground: scheme.onPrimary,
              onTap: () {
                _close();
                widget.onRead();
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _ActionTile(
              icon: Icons.delete_outline,
              label: s.linksDelete,
              background: scheme.error,
              foreground: scheme.onError,
              onTap: () {
                _close();
                widget.onDelete();
              },
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_offset != 0)
            Positioned.fill(
              child: Align(
                alignment:
                    alignLeft ? Alignment.centerLeft : Alignment.centerRight,
                child: actions,
              ),
            ),
          AnimatedContainer(
            duration:
                _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: GestureDetector(
              onTap: _offset != 0 ? _close : null,
              child: AbsorbPointer(
                absorbing: _offset != 0,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
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
}

/// 끄는 동안 손가락 아래 따라다니는 카드 미리보기.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.link});

  final SavedLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = math.min(MediaQuery.sizeOf(context).width * 0.72, 320.0);
    return Transform.translate(
      // 손가락에 가리지 않게 살짝 왼쪽 위에 띄운다.
      offset: Offset(-width / 2, -40),
      child: Transform.rotate(
        angle: -0.03,
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          color: theme.colorScheme.surface,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 50,
                      child: NetworkThumb(url: link.coverUrl),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      link.title ??
                          (link.author == null ? link.code : '@${link.author}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
