import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/quickdrop/quicklink_client.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';

class QuickLinkPage extends StatefulWidget {
  const QuickLinkPage({super.key});
  @override
  State<QuickLinkPage> createState() => _QuickLinkPageState();
}

class _QuickLinkPageState extends State<QuickLinkPage> {
  final _server = TextEditingController();
  final _credential = TextEditingController();
  final _pin = TextEditingController();
  QuickLinkClient? _client;
  Uri? _link;
  bool _consent = false;
  bool _busy = false;
  String _status = '';
  double? _progress;
  int _minutes = 15;
  int _limit = 10;

  @override
  void dispose() {
    final client = _client;
    if (client != null) unawaited(client.revoke().catchError((Object _) {}));
    _server.dispose();
    _credential.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _update(String status, [double? progress]) {
    if (mounted) {
      setState(() {
        _status = status;
        _progress = progress;
      });
    }
  }

  Future<void> _start(List<CrossFile> files) async {
    setState(() => _busy = true);
    try {
      if (_pin.text.isNotEmpty && !RegExp(r'^[0-9]{6,12}$').hasMatch(_pin.text)) throw const FormatException('Invalid PIN');
      final client = QuickLinkClient(base: Uri.parse(_server.text.trim()), credential: _credential.text.trim());
      _client = client;
      final selected = List<CrossFile>.unmodifiable(files);
      final link = await client.create(files: selected, pin: _pin.text, minutes: _minutes, limit: _limit, onStatus: (status) => _update(status));
      _credential.clear();
      _pin.clear();
      if (!mounted) {
        await client.revoke();
        return;
      }
      setState(() {
        _link = link;
        _status = 'Share active. Keep QuickDrop open and in the foreground.';
      });
      unawaited(
        client.serve(selected, (status, progress) => _update(status, progress)).catchError((Object _) {
          _update('Share unavailable or expired. Stop it and create a new share to retry.');
        }),
      );
    } catch (_) {
      _client?.close();
      _client = null;
      _update('Unable to create share. Check the HTTPS server, sender credential, PIN, file access, and network connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _client?.revoke();
      _update('Share revoked.');
    } catch (_) {
      _update('Sender stopped. Relay revocation could not be confirmed; the link expires at its configured time.');
    } finally {
      _client = null;
      if (mounted) {
        setState(() {
          _link = null;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch(selectedSendingFilesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('QuickLink')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.public, size: 64),
              const SizedBox(height: 20),
              Text('Across networks.\nStill in your control.', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              const Text(
                'Local transfers stay direct. QuickLink is a separate, optional internet mode requiring a deployed QuickLink server and a sender credential from its operator.',
              ),
              const SizedBox(height: 12),
              const Text(
                'This release streams through your chosen HTTPS relay, without saving files on its disk. The operator can access file contents and metadata in transit. This is transport encryption, not end-to-end encryption. Direct internet peer-to-peer is not yet implemented.',
              ),
              const SizedBox(height: 24),
              if (_link == null) ...[
                Text('${files.length} selected files. Select files in Send before creating a link.'),
                const SizedBox(height: 20),
                TextField(
                  controller: _server,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Your relay HTTPS origin', hintText: 'https://share.example.com'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _credential,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Sender credential (kept in memory only)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pin,
                  enabled: !_busy,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: const InputDecoration(labelText: 'Optional PIN (6–12 digits)'),
                ),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    DropdownButton<int>(
                      value: _minutes,
                      onChanged: _busy ? null : (v) => setState(() => _minutes = v!),
                      items: [15, 60, 1440].map((v) => DropdownMenuItem(value: v, child: Text('Expires in $v minutes'))).toList(),
                    ),
                    DropdownButton<int>(
                      value: _limit,
                      onChanged: _busy ? null : (v) => setState(() => _limit = v!),
                      items: [1, 10, 100].map((v) => DropdownMenuItem(value: v, child: Text('$v file download attempts'))).toList(),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _consent,
                  onChanged: _busy ? null : (v) => setState(() => _consent = v!),
                  title: const Text('I choose this relay and consent to streaming my selected files through it.'),
                ),
                FilledButton.icon(
                  onPressed: _busy || !_consent || files.isEmpty ? null : () => _start(files),
                  icon: const Icon(Icons.link),
                  label: const Text('Create temporary link'),
                ),
              ] else ...[
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(width: 220, child: PrettyQrView.data(data: _link.toString())),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('The full link grants access. Send its PIN separately. Recipients use a browser; no account is needed.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _link.toString()));
                    _update('Link copied. Clear your clipboard after sharing it.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy private link'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop and revoke share'),
                ),
              ],
              if (_busy || _progress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: LinearProgressIndicator(value: _progress),
                ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Semantics(liveRegion: true, child: Text(_status)),
                ),
              const SizedBox(height: 24),
              const Text(
                'Downloads run one file at a time per share. Interrupted downloads restart the full file and consume another attempt. Large browser downloads require streaming save support. iOS and Android may suspend transfers in the background. No silent uploads, cloud storage, or automatic relay fallback.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
