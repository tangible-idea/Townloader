import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/ig_post.dart';
import '../models/ig_user.dart';
import '../services/download_service.dart';
import '../state/profile_controller.dart';
import '../state/settings_controller.dart';
import 'format.dart';
import 'widgets/download_options_sheet.dart';
import 'widgets/network_thumb.dart';
import 'widgets/state_views.dart';
import 'widgets/personal_use_notice.dart';

/// 계정 하나의 게시물·릴스·스토리를 훑어보고 골라 받는 화면.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onOpenDownloads});

  /// 큐에 파일을 넣은 뒤 진행 상황을 보여 주기 위해 목록 탭으로 넘어간다.
  final VoidCallback onOpenDownloads;

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 다른 화면에서 `@계정` 을 눌렀을 때 바로 열어 주기 위한 진입점.
  void openUsername(String username) {
    _controller.text = username;
    context.read<ProfileController>().open(username);
  }

  void _onScroll() {
    final controller = context.read<ProfileController>();
    if (!controller.hasMore || controller.isLoadingMore) return;
    // 바닥 가까이 오면 다음 페이지를 미리 불러온다.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 600) {
      controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<SettingsController>();
    final controller = context.watch<ProfileController>();

    return Scaffold(
      appBar: AppBar(title: Text(s.profileTitle)),
      body: SafeArea(
        child: Column(
          children: [
            _searchBar(context),
            const Divider(height: 1),
            Expanded(
              child: settings.isLoaded && !settings.hasApiKey
                  ? MessageView(
                      icon: Icons.key_outlined,
                      title: s.privateAccount,
                      description: null,
                    )
                  : _body(context, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: s.usernameHint,
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: _search, child: Text(s.open)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ProfileController controller) {
    final s = S.of(context);
    if (controller.isLoading && controller.user == null) {
      return LoadingView(label: s.fetching);
    }

    final error = controller.error;
    if (error != null && controller.posts.isEmpty) {
      return MessageView(
        isError: true,
        icon: Icons.error_outline,
        title: s.failedToLoad,
        description: error,
      );
    }

    final user = controller.user;
    if (user == null) {
      return MessageView(
        icon: Icons.person_search_outlined,
        title: s.searchPromptTitle,
        description: s.searchPromptDesc,
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _profileHeader(context, user, controller)),
        if (controller.isLoading)
          const SliverFillRemaining(hasScrollBody: false, child: LoadingView())
        else if (controller.posts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: MessageView(
              icon: Icons.inbox_outlined,
              title: controller.feed.localizedLabel(s.isKo),
              description: user.isPrivate ? s.privateAccount : null,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: controller.posts.length,
              itemBuilder: (context, index) =>
                  _gridTile(context, controller.posts[index]),
            ),
          ),
        if (controller.isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _profileHeader(
    BuildContext context,
    IgUser user,
    ProfileController controller,
  ) {
    final theme = Theme.of(context);
    final s = S.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: ClipOval(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: NetworkThumb(
                      url: user.profilePicUrl,
                      icon: Icons.person_outline,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.fullName.isEmpty
                                ? '@${user.username}'
                                : user.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (user.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        s.postsStat(Fmt.count(user.mediaCount, isKo: s.isKo)),
                        s.followersStat(
                          Fmt.count(user.followerCount, isKo: s.isKo),
                        ),
                        if (user.isPrivate) s.privateBadge,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<ProfileFeed>(
                  segments: [
                    for (final feed in ProfileFeed.values)
                      ButtonSegment(
                        value: feed,
                        label: Text(feed.localizedLabel(S.of(context).isKo)),
                      ),
                  ],
                  selected: {controller.feed},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      controller.switchFeed(selection.first),
                ),
              ),
            ],
          ),
          if (controller.posts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  // 계정명 입력창에 포커스가 남아 있으면 키보드가 목록을 가린다.
                  FocusScope.of(context).unfocus();
                  if (!await confirmPersonalUse(context) || !context.mounted) {
                    return;
                  }

                  final settings = context.read<SettingsController>();
                  final count = context.read<DownloadService>().enqueueAll(
                    controller.posts,
                    quality: settings.quality,
                  );
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(S.of(context).downloadStarted(count)),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  // 큐에 실제로 들어간 게 있을 때만 넘어간다.
                  if (count > 0) widget.onOpenDownloads();
                },
                icon: const Icon(Icons.download),
                label: Text(
                  S.of(context).downloadVisible(controller.posts.length),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gridTile(BuildContext context, IgPost post) {
    final settings = context.read<SettingsController>();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onLongPress: () => DownloadOptionsSheet.show(context, post),
      onTap: () async {
        if (!await confirmPersonalUse(context) || !context.mounted) return;
        final count = context.read<DownloadService>().enqueuePost(
          post,
          quality: settings.quality,
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('$count개 파일을 다운로드에 추가했습니다.'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkThumb(url: post.coverUrl),
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                switch (post.kind) {
                  PostKind.reel => Icons.movie_creation_outlined,
                  PostKind.carousel => Icons.collections_outlined,
                  PostKind.video => Icons.play_circle_outline,
                  PostKind.story => Icons.auto_awesome_outlined,
                  PostKind.photo => Icons.photo_outlined,
                },
                size: 18,
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 4)],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  post.items.length > 1
                      ? S.of(context).itemCountShort(post.items.length)
                      : Fmt.duration(post.items.first.durationSeconds),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _search() {
    final raw = _controller.text.trim().replaceAll('@', '');
    if (raw.isEmpty) return;
    FocusScope.of(context).unfocus();
    context.read<ProfileController>().open(raw.toLowerCase());
  }
}
