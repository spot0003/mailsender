import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:path/path.dart' as p;
import 'package:uri_content/uri_content.dart';

/// Explicit HTTPS streaming relay. No automatic fallback from local transfers.
/// Credentials are kept in memory; redirects never receive them.
class QuickLinkClient {
  final Uri base;
  final String credential;
  final HttpClient _http;
  bool _closed = false;
  String? _id;
  String? _owner;

  QuickLinkClient({required this.base, required this.credential, SecurityContext? securityContext})
    : _http = HttpClient(context: securityContext)..connectionTimeout = const Duration(seconds: 20) {
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path != '' && base.path != '/')) {
      throw const FormatException('Use an HTTPS relay origin, without a path or embedded credentials.');
    }
    _http.idleTimeout = const Duration(seconds: 45);
  }

  Stream<List<int>> source(CrossFile file) {
    if (file.bytes != null) return Stream.value(file.bytes!);
    if (file.path == null) throw StateError('This file must be selected again.');
    if (file.path!.startsWith('content://')) return UriContent().getContentStream(Uri.parse(file.path!));
    return File(file.path!).openRead();
  }

  Future<HttpClientResponse> _request(String method, String path, {Object? body, String? token}) async {
    if (_closed) throw StateError('Share stopped.');
    final request = await _http.openUrl(method, base.resolve(path));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${token ?? credential}');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    return request.close().timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> _json(HttpClientResponse response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Relay request failed (${response.statusCode}). Check credentials, limits, or share expiration.');
    }
    if (response.statusCode == 204) {
      await response.drain<void>();
      return {};
    }
    return jsonDecode(await utf8.decoder.bind(response).join()) as Map<String, dynamic>;
  }

  Future<Uri> create({
    required List<CrossFile> files,
    required String pin,
    required int minutes,
    required int limit,
    required void Function(String) onStatus,
  }) async {
    final specs = <Map<String, Object>>[];
    for (final file in files) {
      if (_closed) throw StateError('Share stopped.');
      onStatus('Preparing ${specs.length + 1} of ${files.length}…');
      final hash = await sha256.bind(source(file)).first;
      specs.add({'name': p.basename(file.name), 'size': file.size, 'sha256': hash.toString()});
    }
    final response = await _json(
      await _request(
        'POST',
        '/api/shares',
        body: {
          'files': specs,
          'pin': pin,
          'expires_in': minutes * 60,
          'download_limit': limit,
        },
      ),
    );
    _id = response['id'] as String;
    _owner = response['owner_token'] as String;
    return base.resolve('/s/$_id').replace(fragment: response['key'] as String);
  }

  Future<void> serve(List<CrossFile> files, void Function(String, double?) onStatus) async {
    while (!_closed) {
      final next = await _json(await _request('GET', '/api/shares/$_id/next', token: _owner));
      if (next.isEmpty) continue;
      final index = next['file_index'] as int;
      if (index < 0 || index >= files.length) throw StateError('Invalid relay file request.');
      final file = files[index];
      final request = await _http.postUrl(base.resolve('/api/shares/$_id/transfers/${next['transfer_id']}/upload'));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_owner');
      request.headers.contentType = ContentType.binary;
      request.contentLength = file.size;
      var sent = 0;
      final start = DateTime.now();
      var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await request
            .addStream(
              source(file).map((chunk) {
                sent += chunk.length;
                final now = DateTime.now();
                if (now.difference(lastUpdate).inMilliseconds > 200) {
                  lastUpdate = now;
                  final elapsed = now.difference(start).inMilliseconds / 1000;
                  final speed = elapsed > 0 ? sent / elapsed : 0.0;
                  final eta = speed > 0 ? ((file.size - sent) / speed).ceil() : 0;
                  onStatus(
                    'Sending ${file.name} · ${(speed / 1048576).toStringAsFixed(1)} MB/s · ${eta}s left',
                    file.size == 0 ? 1 : sent / file.size,
                  );
                }
                return chunk;
              }),
            )
            .timeout(const Duration(hours: 24));
        await _json(await request.close().timeout(const Duration(seconds: 70)));
        onStatus('File delivered to relay. Ready for the next download.', null);
      } catch (_) {
        request.abort();
        if (_closed) return;
        onStatus('Download interrupted. The recipient can retry the complete file while the share is active.', null);
      }
    }
  }

  Future<void> revoke() async {
    try {
      if (_id != null && !_closed) await _json(await _request('DELETE', '/api/shares/$_id', token: _owner));
    } finally {
      close();
    }
  }

  void close() {
    _closed = true;
    _http.close(force: true);
  }
}
