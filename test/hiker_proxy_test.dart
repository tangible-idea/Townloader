import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:townloader/data/hiker_client.dart';

void main() {
  test('프록시가 있으면 키 없이 프록시 경로로 보내고 앱 토큰을 붙인다', () async {
    late http.Request sent;
    final client = HikerClient(
      readApiKey: () => null,
      proxyUrl: 'https://proxy.test',
      appToken: 'token',
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'pk': '1'}), 200);
      }),
    );

    final data = await client.get(
      '/v1/media/by/code',
      query: {'code': 'DchLnq8E21N', 'empty': '', 'none': null},
    );

    expect(data, {'pk': '1'});
    expect(
      sent.url.toString(),
      'https://proxy.test/hiker/v1/media/by/code?code=DchLnq8E21N',
    );
    expect(sent.headers['x-app-token'], 'token');
    expect(sent.headers.containsKey('x-access-key'), isFalse);
  });

  test('프록시가 없으면 예전처럼 키로 HikerAPI 를 직접 부른다', () async {
    late http.Request sent;
    final client = HikerClient(
      readApiKey: () => 'key',
      proxyUrl: '',
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response('{}', 200);
      }),
    );

    await client.get('/v1/user/by/username', query: {'username': 'a'});

    expect(sent.url.host, 'api.hikerapi.com');
    expect(sent.headers['x-access-key'], 'key');
  });

  test('프록시가 경로를 막으면 오류로 바꾼다', () async {
    final client = HikerClient(
      readApiKey: () => null,
      proxyUrl: 'https://proxy.test',
      appToken: 'token',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'not allowed'}), 403),
      ),
    );

    expect(
      () => client.get('/v1/user/by/username'),
      throwsA(isA<HikerException>().having((e) => e.statusCode, 'status', 403)),
    );
  });
}
