import 'ig_post.dart';

/// 스레드 트리에서 글이 차지하는 자리.
enum ThreadRole {
  /// 링크가 가리키는 글.
  root,

  /// 작성자가 이어서 단 글(1/N, 2/N …).
  continuation,

  /// 다른 사람의 댓글. 댓글의 답글은 [ThreadNode.depth] 가 하나 더 깊다.
  reply,
}

class ThreadNode {
  const ThreadNode({
    required this.post,
    required this.role,
    required this.depth,
  });

  final IgPost post;
  final ThreadRole role;

  /// 들여쓰기 단계. 본문과 이어지는 글은 0, 댓글은 1, 댓글의 답글은 2.
  final int depth;

  /// 작성자의 글(본문 또는 이어지는 글)인지.
  bool get isByAuthor => role != ThreadRole.reply;
}

/// Threads 게시물 하나와 그 아래 이어지는 글·댓글을 화면 순서대로 담는다.
class ThreadsThread {
  ThreadsThread({required List<ThreadNode> nodes, this.hasMoreReplies = false})
    : assert(nodes.isNotEmpty && nodes.first.role == ThreadRole.root),
      nodes = List.unmodifiable(nodes);

  final List<ThreadNode> nodes;

  /// 로그인 없이 받는 페이지에는 댓글 첫 묶음만 실린다. 더 있으면 true.
  final bool hasMoreReplies;

  IgPost get root => nodes.first.post;

  /// 이어지는 글도 댓글도 없는 단독 게시물인지.
  bool get isSinglePost => nodes.length == 1;

  /// 링크가 가리키는 글. 미디어가 없으면 빈 목록이다.
  List<IgPost> get mainPosts => [
    if (root.hasDownloadableAssets) root,
  ];

  /// 댓글까지 포함해 미디어가 있는 모든 글.
  List<IgPost> get allPosts => [
    for (final node in nodes)
      if (node.post.hasDownloadableAssets) node.post,
  ];

  int get authorPostCount => nodes.where((node) => node.isByAuthor).length;

  int get replyCount =>
      nodes.where((node) => node.role == ThreadRole.reply).length;

  static int fileCount(List<IgPost> posts) => posts.fold(
    0,
    (sum, post) => sum + post.items.where((item) => item.hasAssets).length,
  );
}
