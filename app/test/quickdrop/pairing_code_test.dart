import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/quickdrop/pairing_code.dart';

void main() {
  final fingerprint = List.filled(64, 'A').join();
  test('trusted local pairing round-trips certificate identity and port', () {
    final code = PairingCode(host: '192.168.10.22', port: 53317, fingerprint: fingerprint);
    final parsed = PairingCode.parse(code.encode());
    expect(parsed.host, code.host);
    expect(parsed.port, code.port);
    expect(parsed.fingerprint, fingerprint);
  });
  test('supports private and scoped link-local IPv6', () {
    for (final host in ['fd00::1', 'fe80::1%3']) {
      expect(PairingCode.parse(PairingCode(host: host, port: 53317, fingerprint: fingerprint).encode()).host, host);
    }
  });
  test('rejects external addresses, DNS names and invalid certificate fingerprints', () {
    for (final host in ['8.8.8.8', 'example.com', '127.0.0.1', '::1', '2001:4860:4860::8888', '192.168.1.1%evil']) {
      expect(() => PairingCode.parse(PairingCode(host: host, port: 53317, fingerprint: fingerprint).encode()), throwsFormatException);
    }
    expect(() => PairingCode.parse(PairingCode(host: '10.0.0.2', port: 0, fingerprint: fingerprint).encode()), throwsFormatException);
    expect(() => PairingCode.parse(PairingCode(host: '10.0.0.2', port: 53317, fingerprint: 'forged').encode()), throwsFormatException);
    expect(() => PairingCode.parse('https://example.com/'), throwsFormatException);
  });
}
