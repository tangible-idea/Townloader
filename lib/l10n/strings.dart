import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 간결한 다국어 문구 (한국어 / 영어 자동 전환).
class S {
  final bool isKo;
  const S(this.isKo);

  static S of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode;
    return S(code != 'en');
  }

  /// 위젯 트리 밖(데이터·서비스 계층)에서 쓰는 문구. 기기 언어를 보고 [of] 와 같은
  /// 규칙(영어가 아니면 한국어)으로 고르므로 화면과 언어가 어긋나지 않는다.
  static S get current =>
      S(WidgetsBinding.instance.platformDispatcher.locale.languageCode != 'en');

  // ── Navigation ──
  String get navDownload => isKo ? '다운로드' : 'Download';
  String get navProfile => isKo ? '프로필' : 'Profile';
  String get navDownloads => isKo ? '목록' : 'Downloads';
  String get navSettings => isKo ? '설정' : 'Settings';

  // ── Home ──
  String get homeTitle => isKo ? '다운로드' : 'Download';
  String get linkHint => isKo ? '링크 붙여넣기' : 'Paste link';
  String get linkSubtitle => 'Instagram & Threads';
  String get paste => isKo ? '붙여넣기' : 'Paste';
  String get clear => isKo ? '지우기' : 'Clear';
  String get fetch => isKo ? '가져오기' : 'Fetch';
  String get fetching => isKo ? '가져오는 중…' : 'Fetching…';
  String get emptyHomeTitle => isKo ? '링크를 입력하세요' : 'Paste a link';
  String get emptyHomeDesc =>
      isKo ? 'Instagram 및 Threads 링크' : 'Instagram & Threads links';
  String get downloadAll => isKo ? '전체 받기' : 'Download all';
  String downloadStarted(int count) =>
      isKo ? '$count개 다운로드 시작' : 'Started $count downloads';
  String get failedToLoad => isKo ? '가져오지 못했습니다' : 'Failed to load';
  String profileLinkNotice(String username) =>
      isKo ? '@$username 프로필 링크입니다' : '@$username profile link';
  String openProfile(String username) =>
      isKo ? '@$username 열기' : 'Open @$username';
  String get openSettings => isKo ? '설정' : 'Settings';

  // ── Post Card ──
  String get linkCopied => isKo ? '링크 복사됨' : 'Link copied';
  String get copyLink => isKo ? '링크 복사' : 'Copy link';
  String get openOriginal => isKo ? '원문 열기' : 'Open original';
  String get openOriginalFailed =>
      isKo ? '원문을 열 수 없습니다.' : "Couldn't open the original post.";

  // ── 개인 보관 안내 ──
  String get personalUseTitle => isKo ? '저장하기 전에' : 'Before you save';
  String get personalUseBody => isKo
      ? '저장한 사진과 영상의 저작권은 원래 올린 사람에게 있습니다.\n\n'
            '개인 보관 용도로만 사용해 주세요. 다른 곳에 다시 올리거나 상업적으로 쓰려면 '
            '먼저 권리자의 허락을 받아야 합니다.'
      : 'The photos and videos you save belong to the people who posted them.\n\n'
            'Keep them for personal use only. Get the rights holder\'s permission '
            'before posting them elsewhere or using them commercially.';
  String get personalUseAgree => isKo ? '동의하고 저장' : 'Agree and save';

  // ── 스레드 요약 ──
  String get summaryTitle => isKo ? 'AI 요약' : 'AI summary';
  String get summaryShow => isKo ? '요약 보기' : 'Show summary';
  String get summaryLoading => isKo ? '요약하는 중…' : 'Summarizing…';
  String get summaryFailed =>
      isKo ? '요약을 만들지 못했습니다.' : "Couldn't create a summary.";
  String get summaryRateLimited => isKo
      ? '오늘 요약할 수 있는 횟수를 다 썼습니다.'
      : "You've reached today's summary limit.";
  String get summaryRetry => isKo ? '다시 시도' : 'Try again';
  String get summaryNote => isKo
      ? 'AI가 만든 요약이라 틀릴 수 있어요. 원문을 함께 확인하세요.'
      : 'Made by AI and may be wrong. Check the original posts.';
  String get aiConsentTitle =>
      isKo ? 'AI로 요약할까요?' : 'Summarize with AI?';
  String aiConsentBody(String provider) => isKo
      ? '요약을 만들기 위해 이 스레드의 공개 글과 댓글 내용이 $provider 로 전송됩니다. '
            '계정 정보나 사진은 보내지 않습니다.'
      : "To create the summary, the public posts and replies in this thread are sent to $provider. "
            'No account information or photos are sent.';
  String get aiConsentAgree => isKo ? '동의하고 요약' : 'Agree and summarize';
  String itemsCount(int count) => isKo ? '$count개 항목' : '$count items';
  String get downloadBtn => isKo ? '다운로드' : 'Download';
  String get savedBtn => isKo ? '저장됨' : 'Saved';
  String get selectQuality => isKo ? '해상도 선택' : 'Select quality';
  String get stories => isKo ? '스토리' : 'Stories';

  // ── Threads 스레드 ──
  String get threadLabel => isKo ? '스레드' : 'Thread';
  String get threadRoot => isKo ? '본문' : 'Post';
  String get threadContinuation => isKo ? '이어지는 글' : 'Thread';
  String get threadReply => isKo ? '댓글' : 'Reply';
  String downloadMainMedia(int files) =>
      isKo ? '본문만 ($files)' : 'This post ($files)';
  String downloadSelected(int files) =>
      isKo ? '선택 받기 ($files)' : 'Download selected ($files)';
  String selectedPosts(int selected, int total) =>
      isKo ? '$total개 중 $selected개 선택' : '$selected of $total selected';
  String authorThreadSection(int count) =>
      isKo ? '작성자 스레드 $count' : 'Author thread · $count';
  String repliesSection(int count) => isKo ? '댓글 $count' : 'Replies · $count';
  String get readReplies => isKo ? '댓글 읽어주기' : 'Read aloud';
  String get stopReading => isKo ? '그만 읽기' : 'Stop';
  String get noThreadMedia =>
      isKo ? '이 스레드에는 받을 미디어가 없습니다.' : 'No media in this thread.';
  String get moreRepliesHidden =>
      isKo ? '댓글은 앞부분만 불러옵니다.' : 'Only the first replies are loaded.';
  String userStories(String username) =>
      isKo ? '@$username 스토리' : "@$username's stories";
  String highlight(String? title) => title == null || title.isEmpty
      ? (isKo ? '하이라이트' : 'Highlight')
      : (isKo ? '하이라이트 · $title' : 'Highlight · $title');
  String itemCountShort(int count) => isKo ? '$count개' : '$count';

  // ── Profile ──
  String get profileTitle => isKo ? '프로필' : 'Profile';
  String get usernameHint => isKo ? '계정명 (예: nasa)' : 'Username (e.g. nasa)';
  String get open => isKo ? '열기' : 'Open';
  String get searchPromptTitle => isKo ? '계정명을 입력하세요' : 'Enter username';
  String get searchPromptDesc =>
      isKo ? '게시물 · 릴스 · 스토리' : 'Posts, reels, and stories';
  String get privateAccount => isKo ? '비공개 계정입니다' : 'Private account';
  String get tabPosts => isKo ? '게시물' : 'Posts';
  String get tabReels => isKo ? '릴스' : 'Reels';
  String get tabStories => isKo ? '스토리' : 'Stories';
  String get noPosts => isKo ? '게시물이 없습니다' : 'No posts';
  String get noReels => isKo ? '릴스가 없습니다' : 'No reels';
  String get noStories => isKo ? '현재 스토리가 없습니다' : 'No active stories';
  String postsStat(String count) => isKo ? '게시물 $count' : '$count posts';
  String followersStat(String count) =>
      isKo ? '팔로워 $count' : '$count followers';
  String get privateBadge => isKo ? '비공개' : 'Private';
  String downloadVisible(int count) =>
      isKo ? '보이는 $count개 전부 받기' : 'Download all $count';

  // ── Downloads ──
  String get downloadsTitle => isKo ? '다운로드 목록' : 'Downloads';
  String get clearFinished => isKo ? '완료 항목 정리' : 'Clear finished';
  String get noDownloadsTitle => isKo ? '다운로드 내역 없음' : 'No downloads';
  String get noDownloadsDesc =>
      isKo ? '저장한 미디어가 여기에 표시됩니다.' : 'Saved media will appear here.';
  String get queued => isKo ? '대기 중' : 'Queued';
  String get failed => isKo ? '실패' : 'Failed';
  String get retry => isKo ? '재시도' : 'Retry';
  String get cancel => isKo ? '취소' : 'Cancel';
  String get photosApp => isKo ? '사진 앱' : 'Photos';
  String savedToAlbum(String album) =>
      isKo ? '사진 앱 · $album 앨범' : 'Photos · $album album';
  String get appDocuments => isKo ? '앱 문서 폴더' : 'App documents';
  String get share => isKo ? '공유' : 'Share';
  String get shareUnavailable => isKo
      ? '파일이 남아 있지 않습니다. 다시 받아 주세요.'
      : 'The file is no longer available. Download it again.';
  String get pathCopied => isKo ? '경로 복사됨' : 'Path copied';
  String get openFolderFailed =>
      isKo ? '저장 위치를 열 수 없습니다.' : "Couldn't open the saved location.";
  String get openFolder => isKo ? '폴더 열기' : 'Open folder';

  // ── Settings ──
  String get settingsTitle => isKo ? '설정' : 'Settings';
  String get qualitySection => isKo ? '화질' : 'Quality';
  String get qualityBest => isKo ? '최고 화질' : 'Best';
  String get qualityBestSub => isKo ? '원본 해상도' : 'Original resolution';
  String get qualitySmall => isKo ? '저용량' : 'Low size';
  String get qualitySmallSub => isKo ? '최저 해상도' : 'Smallest file size';
  String get saveToPhotos => isKo ? '사진 앱에 저장' : 'Save to Photos';
  String get saveToPhotosSub =>
      isKo ? '끄면 앱 폴더에 저장' : 'Off: save to app folder';
  String get storageSection => isKo ? '저장 위치' : 'Storage';
  String get infoSection => isKo ? '안내' : 'Info';
  String get infoDesc =>
      isKo ? '공개 계정 미디어만 지원합니다.' : 'Only public accounts are supported.';
}
