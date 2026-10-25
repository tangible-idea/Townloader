import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../models/ig_post.dart';

/// 게시물을 원래 서비스(앱이 깔려 있으면 앱, 아니면 브라우저)에서 연다.
Future<void> openOriginal(BuildContext context, IgPost post) async {
  final link = post.permalink;
  var opened = false;
  if (link != null) {
    try {
      opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
  }
  if (opened || !context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(S.of(context).openOriginalFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// 헤더 오른쪽에 두는 "원문 열기" 버튼. 원문 주소가 없으면 그리지 않는다.
class OpenOriginalButton extends StatelessWidget {
  const OpenOriginalButton({super.key, required this.post, this.size = 20});

  final IgPost post;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (post.permalink == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: S.of(context).openOriginal,
      icon: Icon(Icons.open_in_new, size: size),
      onPressed: () => openOriginal(context, post),
    );
  }
}
