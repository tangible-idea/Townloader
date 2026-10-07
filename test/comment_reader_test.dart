import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:townloader/data/poe_tts_client.dart';
import 'package:townloader/services/comment_reader.dart';

/// 재생을 테스트가 직접 끝내는 가짜 플레이어.
class _FakePlayback implements AudioPlayback {
  final played = <Uri>[];
  Completer<void>? _playing;
  var stopped = 0;

  @override
  Future<void> play(Uri url) {
    played.add(url);
    _playing = Completer<void>();
    return _playing!.future;
  }

  void finish() => _playing?.complete();

  @override
  Future<void> stop() async {
    stopped++;
    if (_playing case final playing? when !playing.isCompleted) {
      playing.complete();
    }
  }

  @override
  void dispose() {}
}

void main() {
  group('PoeTtsClient', () {
    test('ElevenLabs Turbo 봇을 OpenAI 호환 형식으로 부른다', () async {
      late http.Request sent;
      final client = PoeTtsClient(
        apiKey: 'poe-key',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': 'https://pfst.cf2.poecdn.net/base/audio/abc.mp3',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final url = await client.synthesize('안녕하세요');

      expect(sent.url.toString(), 'https://api.poe.com/v1/chat/completions');
      expect(sent.headers['authorization'], 'Bearer poe-key');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], 'ElevenLabs-v2.5-Turbo');
      expect(body['messages'], [
        {'role': 'user', 'content': '안녕하세요'},
      ]);
      expect(url.toString(), 'https://pfst.cf2.poecdn.net/base/audio/abc.mp3');
    });

    test('실제 Poe 응답(확장자 없는 오디오 주소 하나)을 그대로 쓴다', () {
      // 2026-10-07 실제 호출 결과와 같은 모양. 주소에 확장자가 없지만 mp3 다.
      const body =
          '{"id":"x","object":"chat.completion","model":"ElevenLabs-v2.5-Turbo",'
          '"choices":[{"index":0,"message":{"role":"assistant","content":'
          '"https://pfst.cf2.poecdn.net/base/audio/beaab3d9a32ee57d"},'
          '"finish_reason":"stop"}],'
          '"usage":{"prompt_tokens":24,"completion_tokens":0,"total_tokens":24}}';

      expect(
        PoeTtsClient.audioUrlFrom(body).toString(),
        'https://pfst.cf2.poecdn.net/base/audio/beaab3d9a32ee57d',
      );
    });

    test('마크다운 링크나 조각 목록으로 와도 주소를 꺼낸다', () {
      String reply(Object content) => jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      });

      expect(
        PoeTtsClient.audioUrlFrom(
          reply('[audio](https://cdn.example/a.mp3)'),
        ).toString(),
        'https://cdn.example/a.mp3',
      );
      expect(
        PoeTtsClient.audioUrlFrom(
          reply([
            {'type': 'text', 'text': 'Here you go: https://cdn.example/b.mp3'},
          ]),
        ).toString(),
        'https://cdn.example/b.mp3',
      );
      // 내용이 비어도 응답 어딘가의 오디오 파일 주소를 찾는다.
      expect(
        PoeTtsClient.audioUrlFrom(
          '{"choices":[{"message":{"content":""}}],'
          '"attachments":[{"url":"https://cdn.example/c.wav"}]}',
        ).toString(),
        'https://cdn.example/c.wav',
      );
      expect(PoeTtsClient.audioUrlFrom(reply('오디오 없음')), isNull);
    });

    test('키·포인트 문제는 알아볼 수 있는 오류로 바꾼다', () async {
      for (final (status, message) in [
        (401, 'Poe API 키가 올바르지 않습니다.'),
        (402, 'Poe 포인트가 부족합니다.'),
      ]) {
        final client = PoeTtsClient(
          apiKey: 'k',
          httpClient: MockClient((_) async => http.Response('{}', status)),
        );
        await expectLater(
          client.synthesize('x'),
          throwsA(
            isA<PoeTtsException>().having((e) => e.message, 'message', message),
          ),
        );
      }
    });
  });

  group('CommentReader', () {
    test('빈 댓글은 건너뛰고 차례로 읽으며, 읽는 동안 다음 음성을 미리 만든다', () async {
      final asked = <String>[];
      final playback = _FakePlayback();
      final reader = CommentReader(
        synthesize: (text) async {
          asked.add(text);
          return Uri.parse('https://audio/$text.mp3');
        },
        playback: playback,
      );

      final done = reader.start(['첫째', '', '셋째']);
      await pumpEventQueue();

      expect(reader.current, 0);
      expect(playback.played, [Uri.parse('https://audio/첫째.mp3')]);
      // 첫 글을 읽는 동안 세 번째 글의 음성을 이미 요청했다.
      expect(asked, ['첫째', '셋째']);

      playback.finish();
      await pumpEventQueue();
      expect(reader.current, 2);
      expect(playback.played.last, Uri.parse('https://audio/셋째.mp3'));

      playback.finish();
      await done;
      expect(reader.isActive, isFalse);
      expect(asked, ['첫째', '셋째']);
    });

    test('멈추면 더 읽지 않는다', () async {
      final playback = _FakePlayback();
      final reader = CommentReader(
        synthesize: (text) async => Uri.parse('https://audio/$text.mp3'),
        playback: playback,
      );

      final done = reader.start(['a', 'b', 'c']);
      await pumpEventQueue();
      await reader.stop();
      await done;

      expect(reader.isActive, isFalse);
      expect(playback.played, hasLength(1));
    });

    test('음성을 못 만들면 멈추고 오류를 남긴다', () async {
      final reader = CommentReader(
        synthesize: (_) async => throw PoeTtsException('Poe 포인트가 부족합니다.'),
        playback: _FakePlayback(),
      );

      await reader.start(['a', 'b']);

      expect(reader.isActive, isFalse);
      expect(reader.error, 'Poe 포인트가 부족합니다.');
    });
  });
}
