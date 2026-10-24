import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Separate encrypted copies. Ordinary received files and exported copies are NOT protected.
/// The OS may back up ciphertext. Losing the PIN means losing vault access.
class VaultStore {
  static const maxFileBytes = 32 * 1024 * 1024;
  static const iterations = 600000;
  final Directory directory;
  final AesGcm _cipher = AesGcm.with256bits();
  SecretKey? _key;
  int _generation = 0;

  VaultStore(this.directory);

  bool get unlocked => _key != null;
  File get _config => File(p.join(directory.path, 'vault.json'));
  Future<bool> get exists => _config.exists();

  void lock() {
    _key = null;
    _generation++;
  }

  static List<int> _random(int count) {
    final random = Random.secure();
    return List.generate(count, (_) => random.nextInt(256));
  }

  Future<void> unlock(String pin, {bool create = false}) async {
    if (!RegExp(r'^[0-9]{6,12}$').hasMatch(pin)) {
      throw const FormatException('Use a PIN of 6–12 digits.');
    }
    final generation = ++_generation;
    _key = null;
    await directory.create(recursive: true);
    final Map<String, dynamic> config;
    if (await _config.exists()) {
      config = jsonDecode(await _config.readAsString()) as Map<String, dynamic>;
      if (config['version'] != 1 || config['iterations'] != iterations) throw const FormatException('Unsupported vault format.');
    } else {
      if (!create) throw StateError('Vault not created.');
      config = {'version': 1, 'iterations': iterations, 'salt': base64Encode(_random(16))};
    }
    final bytes = await compute(_deriveKey, <String, Object>{'pin': pin, 'salt': config['salt'] as String});
    final key = SecretKey(bytes);
    if (config['check'] != null) {
      await _cipher.decrypt(_decodeBox(config['check'] as String), secretKey: key, aad: utf8.encode('QuickDrop.vault.v1.check'));
    } else {
      config['check'] = base64Encode(
        (await _cipher.encrypt(utf8.encode('QuickDrop vault'), secretKey: key, aad: utf8.encode('QuickDrop.vault.v1.check'))).concatenation(),
      );
      // Never replace an existing configuration while creating a vault.
      final handle = await _config.open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
        if (await handle.length() != 0) throw StateError('Vault already exists. Unlock it instead.');
        await handle.writeString(jsonEncode(config));
        await handle.flush();
      } finally {
        await handle.close();
      }
    }
    if (_generation != generation) throw StateError('Vault locked. Unlock again to continue.');
    _key = key;
  }

  static Future<List<int>> _deriveKey(Map<String, Object> data) async {
    final algorithm = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return (await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(data['pin'] as String)),
      nonce: base64Decode(data['salt'] as String),
    )).extractBytes();
  }

  SecretBox _decodeBox(String data) => SecretBox.fromConcatenation(base64Decode(data), nonceLength: 12, macLength: 16);

  Future<List<File>> files() async {
    if (!unlocked) throw StateError('Vault locked.');
    return directory.list().where((e) => e is File && e.path.endsWith('.qdv')).cast<File>().toList();
  }

  Future<void> importBytes(String name, Uint8List bytes) async {
    final key = _key;
    if (key == null) throw StateError('Vault locked.');
    if (bytes.length > maxFileBytes) throw StateError('Vault imports are limited to 32 MB per file in this release.');
    final id = base64UrlEncode(_random(24));
    final plain = utf8.encode(
      jsonEncode({'name': p.basename(name), 'bytes': base64Encode(bytes), 'created': DateTime.now().toUtc().toIso8601String()}),
    );
    final box = await _cipher.encrypt(plain, secretKey: key, aad: utf8.encode('QuickDrop.vault.v1.$id'));
    final temp = File(p.join(directory.path, '$id.partial'));
    try {
      await temp.writeAsBytes(box.concatenation(), flush: true);
      await temp.rename(p.join(directory.path, '$id.qdv'));
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<VaultFile> read(File file) async {
    final key = _key;
    final generation = _generation;
    if (key == null) throw StateError('Vault locked.');
    if (p.dirname(file.path) != directory.path || !file.path.endsWith('.qdv')) throw StateError('Invalid vault entry.');
    if (await file.length() > maxFileBytes * 2) throw StateError('Vault entry exceeds the supported size.');
    final id = p.basenameWithoutExtension(file.path);
    final plain = await _cipher.decrypt(
      SecretBox.fromConcatenation(await file.readAsBytes(), nonceLength: 12, macLength: 16),
      secretKey: key,
      aad: utf8.encode('QuickDrop.vault.v1.$id'),
    );
    if (_generation != generation || !unlocked) throw StateError('Vault locked.');
    final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return VaultFile(p.basename(data['name'] as String), base64Decode(data['bytes'] as String));
  }
}

class VaultFile {
  final String name;
  final Uint8List bytes;
  const VaultFile(this.name, this.bytes);
}
