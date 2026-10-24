import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/quickdrop/vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late VaultStore store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('quickdrop-vault-test-');
    store = VaultStore(directory);
  });
  tearDown(() async {
    store.lock();
    await directory.delete(recursive: true);
  });

  test('encrypted vault persists, rejects wrong PIN, and restores exact bytes', () async {
    await store.unlock('12345678', create: true);
    final bytes = Uint8List.fromList(utf8.encode('private content that must never be stored as plaintext'));
    await store.importBytes('confidential.txt', bytes);
    final files = await store.files();
    expect(files, hasLength(1));
    final encrypted = await files.single.readAsBytes();
    expect(utf8.decode(encrypted, allowMalformed: true), isNot(contains('private content')));
    expect(utf8.decode(encrypted, allowMalformed: true), isNot(contains('confidential.txt')));
    store.lock();
    await expectLater(store.read(files.single), throwsStateError);
    final reopened = VaultStore(directory);
    await expectLater(reopened.unlock('00000000'), throwsA(isA<SecretBoxAuthenticationError>()));
    expect(reopened.unlocked, isFalse);
    await reopened.unlock('12345678');
    final result = await reopened.read(files.single);
    expect(result.name, 'confidential.txt');
    expect(result.bytes, bytes);
    reopened.lock();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('rejects modified ciphertext and substituted vault entry IDs', () async {
    await store.unlock('12345678', create: true);
    await store.importBytes('file.txt', Uint8List.fromList([1, 2, 3, 4, 5]));
    final file = (await store.files()).single;
    final bytes = await file.readAsBytes();
    bytes[15] ^= 1;
    await file.writeAsBytes(bytes);
    await expectLater(store.read(file), throwsA(isA<SecretBoxAuthenticationError>()));
    bytes[15] ^= 1;
    await file.writeAsBytes(bytes);
    final moved = await file.rename('${directory.path}/different-id.qdv');
    await expectLater(store.read(moved), throwsA(isA<SecretBoxAuthenticationError>()));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('lock during key derivation cannot reopen the vault', () async {
    final pending = store.unlock('12345678', create: true);
    store.lock();
    await expectLater(pending, throwsStateError);
    expect(store.unlocked, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
