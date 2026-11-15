import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pio_photo_layout/online/net.dart';

Future<NetException> failure(Future<Object?> f) async {
  try {
    await f;
  } on NetException catch (e) {
    return e;
  }
  fail('expected a NetException');
}

void main() {
  final uri = Uri.https('pio.bongabong.gov.ph', '/download/latest.json');

  test('a client that cannot connect gives the offline message', () async {
    final net = Net(client: MockClient((_) async => throw http.ClientException('Failed host lookup')));
    expect((await failure(net.getJson(uri))).message, kOfflineMessage);
  });

  test('any other client failure also reads as offline', () async {
    final net = Net(client: MockClient((_) async => throw StateError('boom')));
    expect((await failure(net.getJson(uri))).message, kOfflineMessage);
  });

  test('a client that never answers gives the no-answer message', () async {
    final net = Net(client: MockClient((_) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 50));
    expect((await failure(net.getJson(uri))).message, kNoAnswerMessage);
  });

  test('500 gives the server-trouble message with the status', () async {
    final net = Net(client: MockClient((_) async => http.Response('oops', 500)));
    final e = await failure(net.getJson(uri));
    expect(e.message, kServerTroubleMessage);
    expect(e.status, 500);
  });

  test('a 429 with an error sentence gives exactly that sentence', () async {
    const s = 'Too many layouts were sent from this connection today. Try again tomorrow.';
    final net = Net(client: MockClient((_) async => http.Response(jsonEncode({'error': s}), 429, headers: {'content-type': 'application/json'})));
    final e = await failure(net.postForm(uri, fields: {'a': 'b'}));
    expect(e.message, s);
    expect(e.status, 429);
  });

  test('200 with broken JSON gives the server-trouble message', () async {
    final net = Net(client: MockClient((_) async => http.Response('{not json', 200)));
    expect((await failure(net.getJson(uri))).message, kServerTroubleMessage);
  });

  test('getJson sends the headers and decodes', () async {
    late http.Request seen;
    final net = Net(client: MockClient((r) async {
      seen = r;
      return http.Response('{"a":1}', 200);
    }));
    expect(await net.getJson(uri), {'a': 1});
    expect(seen.headers['Accept'] ?? seen.headers['accept'], 'application/json');
    expect(seen.headers['Cache-Control'] ?? seen.headers['cache-control'], 'no-cache');
    expect(seen.headers['User-Agent'] ?? seen.headers['user-agent'], 'elayout-app');
  });

  test('getBytes over maxBytes fails', () async {
    final net = Net(client: MockClient((_) async => http.Response.bytes(Uint8List(2000), 200)));
    expect(await net.getBytes(uri), hasLength(2000));
    await failure(net.getBytes(uri, maxBytes: 1000));
  });

  test('postForm sends fields and files as multipart', () async {
    late http.BaseRequest seen;
    final net = Net(client: MockClient.streaming((r, body) async {
      seen = r;
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{"ok":true}')), 200);
    }));
    final r = await net.postForm(uri, fields: {'name': 'x'}, files: {'file': NetFile('a.json', 'application/json', Uint8List.fromList([1, 2]))});
    expect(r, {'ok': true});
    expect(seen.headers['content-type'], startsWith('multipart/form-data'));
  });
}
