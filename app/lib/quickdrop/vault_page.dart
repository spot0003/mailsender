import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/quickdrop/vault_biometrics.dart';
import 'package:localsend_app/quickdrop/vault_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with WidgetsBindingObserver {
  final _biometrics = VaultBiometrics();
  bool _biometricsAvailable = false;
  bool _requireBiometrics = false;
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  VaultStore? _store;
  List<File> _files = [];
  PlatformFile? _pendingImport;
  bool _exists = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final dir = await getApplicationSupportDirectory();
    final store = VaultStore(Directory(p.join(dir.path, 'quickdrop-vault')));
    final exists = await store.exists;
    final available = await _biometrics.available();
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _store = store;
        _exists = exists;
        _biometricsAvailable = available;
        _requireBiometrics = prefs.getBool('qd_vault_biometrics') ?? false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _lock();
  }

  void _lock() {
    _store?.lock();
    _pin.clear();
    _confirm.clear();
    if (mounted) setState(() => _files = []);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store?.lock();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Operation failed. Check your PIN, biometric authentication, available space, or file permissions. After five failed PIN attempts, wait five minutes. No unverified file was exported.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('qd_vault_biometrics') == true && !await _biometrics.authenticate()) {
      throw StateError('Biometric authentication was not completed.');
    }
    if ((prefs.getInt('qd_vault_retry_after') ?? 0) > DateTime.now().millisecondsSinceEpoch) {
      throw StateError('Too many PIN attempts.');
    }
    if (!_exists && _pin.text != _confirm.text) throw StateError('PINs must match.');
    final failures = (prefs.getInt('qd_vault_failures') ?? 0) + 1;
    await prefs.setInt('qd_vault_failures', failures);
    if (failures >= 5) await prefs.setInt('qd_vault_retry_after', DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
    await _store!.unlock(_pin.text, create: !_exists);
    await prefs.remove('qd_vault_failures');
    await prefs.remove('qd_vault_retry_after');
    _pin.clear();
    _confirm.clear();
    final pending = _pendingImport;
    if (pending != null) {
      _pendingImport = null;
      await _store!.importBytes(pending.name, await File(pending.path!).readAsBytes());
    }
    final files = await _store!.files();
    if (mounted) {
      setState(() {
        _exists = true;
        _files = files;
      });
    }
  }

  Future<void> _import() async {
    // Native pickers may background the app: collect the file first, then ask to unlock again.
    final selection = await FilePicker.pickFiles(withData: false);
    if (selection == null) return;
    final selected = selection.files.single;
    if (selected.size > VaultStore.maxFileBytes || selected.path == null) throw StateError('Unsupported file.');
    if (!_store!.unlocked) {
      _pendingImport = selected;
      if (mounted) setState(() => _error = 'Unlock the vault again to finish importing the selected file.');
      return;
    }
    final bytes = await File(selected.path!).readAsBytes();
    await _store!.importBytes(selected.name, bytes);
    bytes.fillRange(0, bytes.length, 0);
    await FilePicker.clearTemporaryFiles();
    final files = await _store!.files();
    if (mounted) setState(() => _files = files);
  }

  Future<void> _export(File file) async {
    final data = await _store!.read(file);
    if (!mounted || !_store!.unlocked) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export an unprotected copy?'),
        content: const Text('The exported file will be readable by other apps with access to that location. The encrypted vault copy remains.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Export')),
        ],
      ),
    );
    if (accepted != true || !_store!.unlocked) return;
    final destination = await FilePicker.saveFile(fileName: data.name, bytes: data.bytes);
    if (destination != null) data.bytes.fillRange(0, data.bytes.length, 0);
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _store?.unlocked ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickVault'),
        actions: [if (unlocked) IconButton(onPressed: _busy ? null : _lock, icon: const Icon(Icons.lock_outline), tooltip: 'Lock')],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.shield_outlined, size: 64),
              const SizedBox(height: 20),
              Text(unlocked ? 'Your private space' : 'A little more private.', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text(
                'Import separate encrypted copies protected by your PIN (AES-256-GCM). Original received files stay in their original location. Delete those separately if needed. No PIN recovery. Maximum 32 MB per file.',
              ),
              const SizedBox(height: 24),
              if (!unlocked) ...[
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: InputDecoration(labelText: _exists ? 'PIN (6–12 digits)' : 'Create a PIN (6–12 digits)'),
                ),
                if (!_exists)
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    decoration: const InputDecoration(labelText: 'Confirm PIN'),
                  ),
                FilledButton(onPressed: _busy || _store == null ? null : () => _run(_unlock), child: Text(_exists ? 'Unlock vault' : 'Create vault')),
              ] else ...[
                if (_biometricsAvailable)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require biometrics and PIN'),
                    subtitle: const Text('An additional device check. Your PIN remains necessary.'),
                    value: _requireBiometrics,
                    onChanged: _busy
                        ? null
                        : (enabled) => _run(() async {
                            if (!await _biometrics.authenticate()) throw StateError('Authentication canceled.');
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('qd_vault_biometrics', enabled);
                            if (mounted) setState(() => _requireBiometrics = enabled);
                          }),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(_import),
                  icon: const Icon(Icons.add),
                  label: const Text('Import an encrypted copy'),
                ),
                if (_files.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Your vault is empty. Import a file to get started.')),
                for (var i = 0; i < _files.length; i++)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text('Private file ${i + 1}'),
                    subtitle: const Text('Name remains encrypted until export'),
                    onTap: _busy ? null : () => _run(() => _export(_files[i])),
                    trailing: IconButton(
                      tooltip: 'Delete encrypted copy',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final file = _files[i];
                              final accepted = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete this vault file?'),
                                  content: const Text('This cannot be undone. Original files outside the vault are unaffected.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                  ],
                                ),
                              );
                              if (accepted == true) {
                                await file.delete();
                                final files = await _store!.files();
                                if (mounted) setState(() => _files = files);
                              }
                            }),
                    ),
                  ),
              ],
              if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 24),
              const Text(
                'The vault locks when the app becomes inactive. Optional biometrics add a device check on supported Android, iOS and macOS devices; the PIN still unlocks encryption. PIN strength matters: local retry delays do not prevent offline guessing of a stolen vault.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
