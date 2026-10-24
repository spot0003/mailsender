import 'dart:io';

/// A local address plus certificate fingerprint, not a password or remote link.
class PairingCode {
  final String host;
  final int port;
  final String fingerprint;
  const PairingCode({required this.host, required this.port, required this.fingerprint});

  static bool isLocalAddress(String host) {
    if (host.contains('%') && !RegExp(r'%[0-9]+$').hasMatch(host)) return false;
    final address = InternetAddress.tryParse(host.split('%').first);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 169 && bytes[1] == 254);
    }
    return (bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  String encode() => Uri(
    scheme: 'quickdrop',
    host: 'pair',
    queryParameters: {
      'v': '1',
      'host': host,
      'port': '$port',
      'fingerprint': fingerprint,
    },
  ).toString();

  static PairingCode parse(String input) {
    if (input.length > 1024) throw const FormatException('Pairing code too long.');
    final uri = Uri.parse(input.trim());
    final query = uri.queryParameters;
    final host = query['host'] ?? '';
    final port = int.tryParse(query['port'] ?? '') ?? 0;
    final fingerprint = query['fingerprint'] ?? '';
    if (uri.scheme != 'quickdrop' ||
        uri.host != 'pair' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasFragment ||
        query['v'] != '1' ||
        !isLocalAddress(host) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-F0-9]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('Invalid local QuickPair code.');
    }
    return PairingCode(host: host, port: port, fingerprint: fingerprint);
  }
}
