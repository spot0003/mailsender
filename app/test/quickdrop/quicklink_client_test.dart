import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/quickdrop/quicklink_client.dart';
import 'package:localsend_isolates/model/file_type.dart';

void main() {
  test('rejects HTTP, embedded credentials and non-origin relay URLs', () {
    for (final value in ['http://example.com', 'https://name:password@example.com', 'https://example.com/path', 'https://example.com?key=test']) {
      expect(() => QuickLinkClient(base: Uri.parse(value), credential: 'test'), throwsFormatException);
    }
  });

  final python = Platform.environment['QUICKDROP_TEST_RELAY_PYTHON'];
  test(
    'Flutter sender streams a selected file to an authenticated HTTPS browser client',
    () async {
      final directory = await Directory.systemTemp.createTemp('quickdrop-https-test-');
      Process? server;
      QuickLinkClient? sender;
      HttpClient? receiver;
      try {
        final cert = '${directory.path}/cert.pem';
        final key = '${directory.path}/key.pem';
        final result = await Process.run('openssl', [
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          key,
          '-out',
          cert,
          '-days',
          '1',
          '-subj',
          '/CN=localhost',
          '-addext',
          'subjectAltName=DNS:localhost,IP:127.0.0.1',
        ]);
        expect(result.exitCode, 0, reason: 'A trusted local TLS fixture must be generated.');
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        final credential = base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)));
        final root = Directory.current.path.endsWith('/app') ? Directory.current.parent.path : Directory.current.path;
        server = await Process.start(
          python!,
          [
            '-m',
            'uvicorn',
            'quicklink.service:app',
            '--host',
            '127.0.0.1',
            '--port',
            '$port',
            '--ssl-certfile',
            cert,
            '--ssl-keyfile',
            key,
            '--no-access-log',
            '--log-level',
            'critical',
          ],
          workingDirectory: root,
          environment: {'QUICKLINK_SENDER_TOKEN': credential},
        );
        unawaited(server.stdout.drain<void>());
        unawaited(server.stderr.drain<void>());
        final origin = Uri.parse('https://127.0.0.1:$port');
        final trust = SecurityContext(withTrustedRoots: false)..setTrustedCertificates(cert);
        receiver = HttpClient(context: trust);
        var ready = false;
        for (var attempt = 0; attempt < 100; attempt++) {
          try {
            final r = await (await receiver.getUrl(origin.resolve('/healthz'))).close();
            await r.drain<void>();
            ready = r.statusCode == 200;
          } catch (_) {}
          if (ready) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(ready, isTrue, reason: 'The HTTPS relay fixture must be listening.');
        final bytes = Uint8List.fromList(List.generate(1024 * 1024 + 17, (i) => i % 251));
        final file = CrossFile(
          name: 'fixture.bin',
          fileType: FileType.other,
          size: bytes.length,
          thumbnail: null,
          asset: null,
          path: null,
          bytes: bytes,
          lastModified: null,
          lastAccessed: null,
        );
        sender = QuickLinkClient(base: origin, credential: credential, securityContext: trust);
        final link = await sender.create(files: [file], pin: '123456', minutes: 15, limit: 1, onStatus: (_) {});
        expect(link.fragment, isNotEmpty);
        final id = link.pathSegments.last;
        final access = await receiver.postUrl(origin.resolve('/api/shares/$id/access'));
        access.headers.contentType = ContentType.json;
        access.write(jsonEncode({'key': link.fragment, 'pin': '123456'}));
        final accessResponse = await access.close();
        expect(accessResponse.statusCode, 200);
        final session = jsonDecode(await utf8.decoder.bind(accessResponse).join()) as Map<String, dynamic>;
        final serving = sender.serve([file], (_, _) {}).catchError((Object _) {});
        final request = await receiver.getUrl(origin.resolve('/api/shares/$id/files/0'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${session['token']}');
        final download = await request.close();
        expect(download.statusCode, 200);
        final received = await download.fold<BytesBuilder>(BytesBuilder(), (all, part) => all..add(part));
        expect(received.takeBytes(), bytes);
        await sender.revoke();
        await serving;
        final expired = await receiver.postUrl(origin.resolve('/api/shares/$id/access'));
        expired.headers.contentType = ContentType.json;
        expired.write(jsonEncode({'key': link.fragment, 'pin': '123456'}));
        final expiredResponse = await expired.close();
        expect(expiredResponse.statusCode, 410);
        await expiredResponse.drain<void>();
      } finally {
        sender?.close();
        receiver?.close(force: true);
        server?.kill();
        if (server != null) await server.exitCode;
        await directory.delete(recursive: true);
      }
    },
    skip: python == null ? 'Set QUICKDROP_TEST_RELAY_PYTHON to the Python executable with quicklink/requirements.lock installed.' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
