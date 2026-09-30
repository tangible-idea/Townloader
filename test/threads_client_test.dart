import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/data/ig_url.dart';
import 'package:townloader/data/threads_client.dart';
import 'package:townloader/models/ig_asset.dart';
import 'package:townloader/models/ig_post.dart';

void main() {
  test('Threads 주소를 공식 embed 경로로 조회한다', () async {
    final httpClient = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://www.threads.com/@instagram/post/DdE9z6Ejw7R/embed',
      );
      expect(request.headers['accept'], contains('text/html'));
      return http.Response('''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>instagram</span></a>
          <div class="SoloMediaContainer">
            <video><source src="https://cdn.example/video.mp4"></video>
          </div>
        </div>
      ''', 200);
    });
    final client = ThreadsClient(httpClient: httpClient);

    final post = await client.fetchPost(
      IgUrlParser.parse(
        'https://www.threads.com/@instagram/post/DdE9z6Ejw7R?xmt=tracking',
      ),
    );

    expect(post.authorName, 'instagram');
    expect(post.items.single.best?.url, 'https://cdn.example/video.mp4');
    client.close();
  });

  test('Threads /share/ 공유 링크의 리디렉션을 추적하여 원본 게시물을 조회한다', () async {
    final httpClient = MockClient((request) async {
      if (request.url.path.contains('/share/')) {
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://www.threads.com/@thkim00/post/DdjE_sbEmK2?xmt=AQG0J1J',
          },
        );
      }
      expect(
        request.url.toString(),
        'https://www.threads.com/@thkim00/post/DdjE_sbEmK2/embed',
      );
      return http.Response('''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>thkim00</span></a>
          <div class="SoloMediaContainer">
            <video><source src="https://cdn.example/thkim.mp4"></video>
          </div>
        </div>
      ''', 200);
    });
    final client = ThreadsClient(httpClient: httpClient);

    final post = await client.fetchPost(
      IgUrlParser.parse('https://www.threads.com/share/FSpD8jz1t/'),
    );

    expect(post.authorName, 'thkim00');
    expect(post.code, 'DdjE_sbEmK2');
    expect(post.items.single.best?.url, 'https://cdn.example/thkim.mp4');
    client.close();
  });

  group('Threads embed 파싱', () {
    test('사진 게시물을 읽고 아바타와 링크 미리보기는 제외한다', () {
      const html = '''
        <div class="OuterContainer">
          <div class="AvatarContainer"><img src="https://cdn.example/avatar.jpg"></div>
          <a class="HeaderLink"><span>natgeo</span></a>
          <div class="VerifiedBadge"></div>
          <span class="BodyTextContainer">  산 정상의 풍경  </span>
          <div class="LinkAttachmentImage"><img src="https://cdn.example/link.jpg"></div>
          <div class="SoloMediaContainer">
            <div class="SingleInnerMediaContainer">
              <img src="https://cdn.example/photo.jpg" width="1440" height="1080">
            </div>
          </div>
        </div>
      ''';

      final post = ThreadsClient.parseEmbed(html, code: 'Dc1NNbgDcmL')!;
      expect(post.kind, PostKind.photo);
      expect(post.user?.username, 'natgeo');
      expect(post.user?.isVerified, isTrue);
      expect(post.caption, '산 정상의 풍경');
      expect(
        post.permalink,
        'https://www.threads.com/@natgeo/post/Dc1NNbgDcmL',
      );
      expect(post.items, hasLength(1));
      expect(post.items.single.kind, AssetKind.photo);
      expect(post.items.single.best?.url, 'https://cdn.example/photo.jpg');
      expect(post.items.single.best?.width, 1440);
    });

    test('source 태그가 있는 동영상을 읽는다', () {
      const html = '''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>instagram</span></a>
          <div class="BodyTextContainer">video post</div>
          <div class="SoloMediaContainer">
            <video poster="https://cdn.example/cover.jpg">
              <source src="https://cdn.example/video.mp4">
            </video>
          </div>
        </div>
      ''';

      final post = ThreadsClient.parseEmbed(html, code: 'DdE9z6Ejw7R')!;
      expect(post.kind, PostKind.video);
      expect(post.items.single.kind, AssetKind.video);
      expect(post.items.single.best?.url, 'https://cdn.example/video.mp4');
      expect(post.items.single.thumbnailUrl, 'https://cdn.example/cover.jpg');
    });

    test('사진과 동영상 여러 개는 캐러셀로 만든다', () {
      const html = '''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>creator</span></a>
          <div class="MediaContainer">
            <img src="https://cdn.example/one.jpg">
            <video><source src="https://cdn.example/two.mp4"></video>
          </div>
        </div>
      ''';

      final post = ThreadsClient.parseEmbed(html, code: 'Carousel01')!;
      expect(post.kind, PostKind.carousel);
      expect(post.items.map((item) => item.kind), [
        AssetKind.photo,
        AssetKind.video,
      ]);
    });

    test('인용 게시물의 미디어는 섞지 않는다', () {
      const html = '''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>writer</span></a>
          <div class="SoloMediaContainer"><img src="https://cdn.example/main.jpg"></div>
          <div class="OuterContainer">
            <div class="SoloMediaContainer"><img src="https://cdn.example/quote.jpg"></div>
          </div>
        </div>
      ''';

      final post = ThreadsClient.parseEmbed(html, code: 'Quoted01')!;
      expect(post.items, hasLength(1));
      expect(post.items.single.best?.url, 'https://cdn.example/main.jpg');
    });

    test('텍스트 전용 게시물은 null을 돌려준다', () {
      const html = '''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>threads</span></a>
          <div class="BodyTextContainer">text only</div>
        </div>
      ''';
      expect(ThreadsClient.parseEmbed(html, code: 'TextOnly01'), isNull);
    });
  });
  group('댓글(답글) embed', () {
    // 실제 embed 구조: 부모 글이 위(BodyContainerParent), 주소의 글이 아래(OuterContainerFull).
    String replyEmbed({
      required String parentMedia,
      required String replyMedia,
    }) =>
        '''
        <div class="EmbedContainer">
          <div class="OuterContainer OuterContainerFollowButton">
            <a class="HeaderLink"><span>parent_author</span></a>
            <div class="BodyContainerParent BodyContainer">
              <div class="BodyTextContainer">본문 글</div>
              $parentMedia
            </div>
          </div>
          <div class="OuterContainer OuterContainerFull OuterContainerFollowButton">
            <a class="HeaderLink"><span>reply_author</span></a>
            <div class="BodyContainerNoThreadLine">
              <div class="BodyTextContainer">댓글</div>
              $replyMedia
            </div>
          </div>
        </div>
      ''';

    const parentVideo = '''
      <div class="SoloMediaContainer">
        <video><source src="https://cdn.example/parent.mp4"></video>
      </div>''';
    const replyPhoto = '''
      <div class="SoloMediaContainer">
        <img src="https://cdn.example/reply.jpg" width="1080" height="1350">
      </div>''';

    test('본문이 아니라 댓글의 미디어를 가져온다', () {
      final post = ThreadsClient.parseEmbed(
        replyEmbed(parentMedia: parentVideo, replyMedia: replyPhoto),
        code: 'REPLY1',
      );

      expect(post, isNotNull);
      expect(post!.authorName, 'reply_author');
      expect(post.caption, '댓글');
      expect(post.items.single.best?.url, 'https://cdn.example/reply.jpg');
    });

    test('본문에는 미디어가 없고 댓글에만 있어도 가져온다', () {
      final post = ThreadsClient.parseEmbed(
        replyEmbed(parentMedia: '', replyMedia: replyPhoto),
        code: 'REPLY2',
      );

      expect(post!.items.single.best?.url, 'https://cdn.example/reply.jpg');
    });

    test('댓글에 미디어가 없으면 본문 미디어로 대신하지 않는다', () {
      final post = ThreadsClient.parseEmbed(
        replyEmbed(parentMedia: parentVideo, replyMedia: ''),
        code: 'REPLY3',
      );

      expect(post, isNull);
    });

    test('OuterContainerFull 표시가 없어도 부모 글은 피한다', () {
      final html = replyEmbed(
        parentMedia: parentVideo,
        replyMedia: replyPhoto,
      ).replaceAll(' OuterContainerFull', '');
      final post = ThreadsClient.parseEmbed(html, code: 'REPLY4');

      expect(post!.items.single.best?.url, 'https://cdn.example/reply.jpg');
    });
  });
}
