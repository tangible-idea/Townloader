import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 간결한 다국어 문구 (한국어 / 영어 자동 전환).
class S {
  final bool isKo;
  const S(this.isKo);

  static String? overrideLanguageCode;

  static S of(BuildContext context) {
    final code =
        overrideLanguageCode ??
        Localizations.maybeLocaleOf(context)?.languageCode;
    return S(code != 'en');
  }

  /// 위젯 트리 밖(데이터·서비스 계층)에서 쓰는 문구. 사용자가 고른 언어가 있으면 그것을,
  /// 없으면 기기 언어를 보고 [of] 와 같은 규칙(영어가 아니면 한국어)으로 고른다.
  static S get current {
    final code =
        overrideLanguageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return S(code != 'en');
  }

  // ── Navigation ──
  String get navDownload => isKo ? '읽기' : 'Read';
  String get navProfile => isKo ? '프로필' : 'Profile';
  String get navDownloads => isKo ? '목록' : 'Downloads';
  String get navLinks => isKo ? '링크' : 'Links';
  String get navSettings => isKo ? '설정' : 'Settings';

  // ── Links ──
  String get linksTitle => isKo ? '링크' : 'Links';
  String get linksHint =>
      isKo ? '인스타그램 링크를 붙여넣으세요' : 'Paste Instagram links';
  String get linksSave => isKo ? '저장' : 'Save';
  String linksSaved(int count, String category) =>
      isKo ? '$category에 $count개 저장했어요' : 'Saved $count to $category';
  String linksSkipped(int duplicates, int unsupported) => [
    if (duplicates > 0) isKo ? '이미 저장한 링크 $duplicates개' : '$duplicates already saved',
    if (unsupported > 0)
      isKo ? '게시물이 아닌 링크 $unsupported개' : '$unsupported not posts',
  ].join(isKo ? ', ' : ', ');
  String get linksNoneFound =>
      isKo ? '인스타그램 게시물 링크를 찾지 못했어요' : 'No Instagram post links found';
  String get linksEmptyTitle =>
      isKo ? '저장한 링크가 없어요' : 'No saved links yet';
  String get linksEmptyDesc => isKo
      ? '여행지나 맛집 글의 링크를 붙여넣으면 장소를 찾아 모아 둬요'
      : 'Paste links to travel or food posts and their places are collected here';
  String get linksAnalyzing => isKo ? '장소 찾는 중…' : 'Finding places…';
  String linksPlaceCount(int count) =>
      isKo ? '장소 $count곳' : (count == 1 ? '1 place' : '$count places');
  String get linksNoPlaces =>
      isKo ? '글에서 장소를 찾지 못했어요' : 'No places found in this post';
  String get linksRetry => isKo ? '다시 찾기' : 'Retry';
  String get linksDelete => isKo ? '삭제' : 'Delete';
  String get linksMove => isKo ? '카테고리 옮기기' : 'Move to category';
  String get linksNewCategory => isKo ? '새 카테고리' : 'New category';
  String get linksCategoryHint => isKo ? '예: 제주 여행' : 'e.g. Tokyo trip';
  String get linksAdd => isKo ? '만들기' : 'Create';
  String get linksApproximate => isKo ? '대략적인 위치' : 'Approximate';
  String get downloadHistory => isKo ? '다운로드 목록' : 'Downloads';
  String get mapOpen => isKo ? '지도로 보기' : 'Show on map';
  String get mapShowAll => isKo ? '전체 보기' : 'Show all';
  String get mapDeletePlace => isKo ? '이 장소 삭제' : 'Delete this place';
  String get mapDeleteHint => isKo
      ? '카드를 위로 밀어도 지울 수 있어요.'
      : 'You can also swipe a card up to remove it.';
  String get mapPlaceDeleted => isKo ? '장소를 지웠어요' : 'Place removed';
  String get undo => isKo ? '되돌리기' : 'Undo';
  String get mapAll => isKo ? '모든 장소' : 'All places';
  String get mapNoPlaces =>
      isKo ? '이 카테고리에는 아직 찾은 장소가 없어요' : 'No places in this category yet';
  String get mapUnavailable =>
      isKo ? '이 빌드에는 지도 키가 없어요' : 'This build has no map key';

  // ── Home ──
  String get homeTitle => isKo ? '읽기' : 'Read';
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
  String get commentSummaryTitle => isKo ? '댓글 요약' : 'Reply summary';
  String get commentSummaryShow =>
      isKo ? '댓글 요약 보기' : 'Summarize replies';
  String get commentSummaryPartial => isKo
      ? '불러온 앞부분 댓글만 요약했어요.'
      : 'Only the replies loaded so far are summarized.';
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

  // ── 계정 · 지도 공유 ──
  String get accountSection => isKo ? '계정' : 'Account';
  String get accountSignedOutDesc => isKo
      ? '로그인하면 링크 탭에 저장한 글과 장소가 서버에 저장되고, 카테고리 지도를 링크로 공유할 수 있어요.'
      : 'Sign in to back up your saved links and places, and share a category map as a link.';
  String get signInGoogle => isKo ? 'Google로 로그인' : 'Sign in with Google';
  String get signInApple => isKo ? 'Apple로 로그인' : 'Sign in with Apple';
  String get signInUnavailable => isKo
      ? '이 빌드에는 로그인이 설정되어 있지 않습니다.'
      : 'Sign-in is not set up in this build.';
  String signedInAs(String who) => isKo ? '$who 로그인됨' : 'Signed in as $who';
  String get syncing => isKo ? '동기화 중…' : 'Syncing…';
  String syncedAt(String time) => isKo ? '$time 동기화됨' : 'Synced $time';
  String get syncNow => isKo ? '지금 동기화' : 'Sync now';
  String get signOut => isKo ? '로그아웃' : 'Sign out';
  String get signOutDesc => isKo
      ? '기기에 저장한 링크는 그대로 남아요.'
      : 'Links saved on this device stay here.';
  String get deleteAccount => isKo ? '계정 삭제' : 'Delete account';
  String get deleteAccountTitle => isKo ? '계정을 삭제할까요?' : 'Delete your account?';
  String get deleteAccountBody => isKo
      ? '서버에 저장한 링크와 공유한 지도가 모두 지워지고, 보낸 공유 링크도 더 열리지 않아요. 이 기기의 링크는 남습니다.'
      : 'Your synced links and shared maps are removed from the server, and links you sent stop working. Links on this device stay.';
  String get delete => isKo ? '삭제' : 'Delete';
  String get shareMap => isKo ? '지도 공유' : 'Share map';
  String shareMapTitle(String category) =>
      isKo ? '$category 지도 공유' : 'Share the $category map';
  String get shareMapBody => isKo
      ? '공유하면 이 카테고리가 공개로 바뀌어요. 링크를 받은 사람은 누구나 저장한 글의 제목, 사진, 캡션(해시태그 제외), 장소, 인스타그램 원문 링크를 볼 수 있어요.'
      : 'Sharing makes this category public. Anyone with the link can see each saved post\'s title, photos, caption (without hashtags), places and a link to the Instagram post.';
  String get sharePostBody => isKo
      ? '공유하면 이 항목의 지도가 공개로 바뀌어요. 링크를 받은 사람은 누구나 이 글의 제목, 사진, 캡션(해시태그 제외), 장소, 인스타그램 원문 링크를 볼 수 있어요.'
      : 'Sharing makes a public map for this post. Anyone with the link can see its title, photos, caption (without hashtags), places and a link to the Instagram post.';
  String get shareMapNeedsSignIn => isKo
      ? '지도를 공유하려면 설정에서 먼저 로그인해 주세요.'
      : 'Sign in from Settings to share a map.';
  String get shareMapAction => isKo ? '공개하고 공유' : 'Make public and share';
  String get sharePublicLabel => isKo ? '공개 중' : 'Public';
  String get shareOpenInBrowser =>
      isKo ? '브라우저로 열기' : 'Open in browser';
  String get shareLinkAgain => isKo ? '링크 다시 보내기' : 'Send link again';
  String get shareStop => isKo ? '공개 중지' : 'Stop sharing';
  String get shareStopped => isKo ? '다시 비공개로 바꿨어요' : 'This map is private again';
  String get sharedMapLoading => isKo ? '공유받은 지도를 불러오는 중…' : 'Loading shared map…';

  // ── Settings ──
  String get settingsTitle => isKo ? '설정' : 'Settings';
  String get languageSection => isKo ? '언어' : 'Language';
  String get languageSystem => isKo ? '기기 설정 따르기' : 'System default';
  String get languageKorean => '한국어';
  String get languageEnglish => 'English';
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
