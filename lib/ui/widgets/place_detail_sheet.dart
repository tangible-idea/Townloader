import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/places_client.dart';
import '../../l10n/strings.dart';
import '../../models/saved_link.dart';
import 'network_thumb.dart';

/// 지도 하단 장소 카드를 눌렀을 때 띄우는 카카오맵 상세·후기 시트.
class PlaceDetailSheet extends StatefulWidget {
  const PlaceDetailSheet({
    super.key,
    required this.place,
    required this.link,
    required this.client,
  });

  final SavedPlace place;
  final SavedLink link;
  final PlacesClient client;

  static Future<void> show(
    BuildContext context, {
    required SavedPlace place,
    required SavedLink link,
    required PlacesClient client,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        PlaceDetailSheet(place: place, link: link, client: client),
  );

  @override
  State<PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<PlaceDetailSheet> {
  late final Future<KakaoPlaceDetail?> _detailFuture = widget.client
      .fetchPlaceDetail(widget.place);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final place = widget.place;
    final link = widget.link;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) => FutureBuilder<KakaoPlaceDetail?>(
        future: _detailFuture,
        builder: (context, snapshot) {
          final detail = snapshot.data;
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final fallbackPhoto = link.photoFor(place);
          final photos = <String>[
            if (detail != null) ...detail.photos,
            if (fallbackPhoto != null &&
                (detail == null || !detail.photos.contains(fallbackPhoto)))
              fallbackPhoto,
          ];

          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              // ── 제목 · 업종 · 별점 ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      place.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (place.category != null && place.category!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(place.category!, style: muted),
                  ],
                  if (detail?.priceLevel != null) ...[
                    const SizedBox(width: 6),
                    Text(detail!.priceLevel!, style: muted),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (place.rating != null && place.rating! > 0)
                    Text(
                      '★ ${place.rating!.toStringAsFixed(1)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (place.reviewCount != null && place.reviewCount! > 0)
                    Text(
                      s.isKo
                          ? '후기 ${place.reviewCount}개'
                          : '${place.reviewCount} reviews',
                      style: muted,
                    ),
                  if (detail?.openStatus != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        detail!.openStatus!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (place.address != null || place.phone != null) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (place.address != null && place.address!.isNotEmpty)
                      place.address!,
                    if (place.phone != null && place.phone!.isNotEmpty)
                      place.phone!,
                  ].join(' · '),
                  style: muted,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (place.placeUrl != null && place.placeUrl!.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: () => launchUrl(
                        Uri.parse(place.placeUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: Text(s.isKo ? '카카오맵에서 보기' : 'Open in KakaoMap'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(link.url),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(s.openOriginal),
                  ),
                ],
              ),

              // ── 사진 갤러리 ──
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 128,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 160,
                        height: 128,
                        child: NetworkThumb(url: photos[index]),
                      ),
                    ),
                  ),
                ),
              ],

              if (loading) ...[
                const SizedBox(height: 28),
                const Center(child: CircularProgressIndicator()),
              ] else if (detail != null) ...[
                // ── 카카오 AI 요약 ──
                if (detail.aiTitle != null ||
                    detail.aiSummary != null ||
                    detail.aiKeywords.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                detail.aiTitle ??
                                    (s.isKo ? 'AI 장소 요약' : 'AI Place Summary'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (detail.aiSummary != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            detail.aiSummary!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                        if (detail.aiKeywords.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final kw in detail.aiKeywords)
                                _SmallTag(label: '#$kw'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // ── 장점 투표 & 태그 ──
                if (detail.strengths.isNotEmpty || detail.tags.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final st in detail.strengths)
                        _SmallTag(
                          label: '${st.name} ${st.count}',
                          emphasized: true,
                        ),
                      for (final tag in detail.tags) _SmallTag(label: '#$tag'),
                    ],
                  ),
                ],

                // ── 영업시간 ──
                if (detail.openHours.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _SectionTitle(s.isKo ? '영업시간' : 'Hours'),
                  const SizedBox(height: 6),
                  for (final line in detail.openHours)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(line, style: theme.textTheme.bodySmall),
                    ),
                ],

                // ── 대표 메뉴 ──
                if (detail.menus.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _SectionTitle(s.isKo ? '메뉴·요금' : 'Menu & Prices'),
                  const SizedBox(height: 6),
                  for (final item in detail.menus)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.name,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    if (item.recommend) ...[
                                      const SizedBox(width: 6),
                                      _SmallTag(
                                        label: s.isKo ? '추천' : 'Pick',
                                        emphasized: true,
                                      ),
                                    ],
                                  ],
                                ),
                                if (item.description != null)
                                  Text(item.description!, style: muted),
                              ],
                            ),
                          ),
                          if (item.price != null)
                            Text(
                              _formatWon(item.price!, s.isKo),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],

                // ── 카카오맵 방문자 후기 ──
                if (detail.visitorReviews.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                    s.isKo
                        ? '방문자 후기 (${detail.visitorReviews.length})'
                        : 'Visitor Reviews (${detail.visitorReviews.length})',
                  ),
                  const SizedBox(height: 8),
                  for (final review in detail.visitorReviews)
                    _VisitorReviewCard(review: review),
                ],

                // ── 블로그 리뷰 ──
                if (detail.blogReviews.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                    s.isKo
                        ? '블로그 리뷰 (${detail.blogReviews.length})'
                        : 'Blog Reviews (${detail.blogReviews.length})',
                  ),
                  const SizedBox(height: 8),
                  for (final blog in detail.blogReviews)
                    _BlogReviewCard(blog: blog),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  static String _formatWon(int price, bool isKo) {
    if (price <= 0) return isKo ? '무료' : 'Free';
    final digits = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return isKo ? '$buf원' : '₩$buf';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: emphasized
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
          fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _VisitorReviewCard extends StatelessWidget {
  const _VisitorReviewCard({required this.review});

  final KakaoVisitorReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final stars = '★' * review.rating.clamp(1, 5);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  stars,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    review.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (review.date != null) Text(review.date!, style: muted),
              ],
            ),
            const SizedBox(height: 6),
            Text(review.contents, style: theme.textTheme.bodyMedium),
            if (review.photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: NetworkThumb(url: review.photos[index]),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BlogReviewCard extends StatelessWidget {
  const _BlogReviewCard({required this.blog});

  final KakaoBlogReview blog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: blog.url == null
            ? null
            : () => launchUrl(
                Uri.parse(blog.url!),
                mode: LaunchMode.externalApplication,
              ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (blog.title.isNotEmpty)
                Text(
                  blog.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (blog.contents.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  blog.contents,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (blog.photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: blog.photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: NetworkThumb(url: blog.photos[index]),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                [blog.author, if (blog.date != null) blog.date!].join(' · '),
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
