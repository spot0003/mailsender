import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/pages/troubleshoot_page.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/quickdrop/pairing_code.dart';
import 'package:localsend_app/widget/dialogs/address_input_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class QuickPairPage extends StatefulWidget {
  const QuickPairPage({super.key});
  @override
  State<QuickPairPage> createState() => _QuickPairPageState();
}

class _QuickPairPageState extends State<QuickPairPage> {
  final _input = TextEditingController();
  String? _status;
  String? _selectedAddress;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final code = PairingCode.parse(_input.text);
      final response = await context
          .read(httpProvider)
          .pinnedTo(code.fingerprint)
          .register(
            protocol: ProtocolType.https,
            ip: code.host,
            port: code.port,
            payload: context.read(deviceFullInfoProvider).toRegisterDto(),
          )
          .timeout(const Duration(seconds: 15));
      final device = response.body.toDevice(code.host, code.port, true);
      if (device.fingerprint != code.fingerprint) throw StateError('Certificate identity mismatch.');
      if (!mounted) return;
      await context.redux(nearbyDevicesProvider).dispatchAsync(RegisterDeviceAction(device));
      if (mounted) setState(() => _status = 'Connected to ${device.alias}. Return to Send to choose files.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Could not verify this device. Check the code, keep both apps open on the same network, enable HTTPS, and check firewall and local-network permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = context.watch(deviceFullInfoProvider);
    final server = context.watch(serverProvider);
    final addresses = context.watch(localIpProvider).localIps.where(PairingCode.isLocalAddress).toList();
    final address = addresses.contains(_selectedAddress) ? _selectedAddress : (addresses.isEmpty ? null : addresses.first);
    final code = address != null && server?.https == true
        ? PairingCode(host: address, port: device.port, fingerprint: device.fingerprint).encode()
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('QuickPair')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Meet your other devices.', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text(
                'No account. No internet. Automatic discovery uses your local network. A QuickPair QR includes the device certificate fingerprint so the connection can verify the device you chose.',
              ),
              const SizedBox(height: 24),
              if (code != null) ...[
                Text(device.alias, style: Theme.of(context).textTheme.titleLarge),
                if (addresses.length > 1)
                  DropdownButton<String>(
                    value: address,
                    isExpanded: true,
                    items: addresses.map((ip) => DropdownMenuItem(value: ip, child: Text(ip))).toList(),
                    onChanged: (ip) => setState(() => _selectedAddress = ip),
                  ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(width: 220, child: PrettyQrView.data(data: code)),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (mounted) setState(() => _status = 'QuickPair code copied.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy my QuickPair code'),
                ),
              ] else
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No encrypted local listener is available. Connect to Wi-Fi, grant local-network permission, and enable HTTPS in Settings.',
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              TextField(
                controller: _input,
                enabled: !_busy,
                maxLength: 1024,
                decoration: const InputDecoration(labelText: 'Paste the other device’s QuickPair code', hintText: 'quickdrop://pair?...'),
              ),
              const Text(
                'Scan the QR using a QR reader that can copy its text, then paste it here. In-app camera scanning is not included. Accept codes only from a device you trust.',
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _connect, child: const Text('Verify and connect')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final found = await showDialog<Device>(context: context, builder: (_) => const AddressInputDialog());
                        if (found != null && context.mounted) {
                          await context.redux(nearbyDevicesProvider).dispatchAsync(RegisterDeviceAction(found));
                          if (mounted) {
                            setState(
                              () => _status =
                                  'Found ${found.alias}. Return to Send. The short code locates the device; it is not an authentication PIN.',
                            );
                          }
                        }
                      },
                child: const Text('Use a short local address code instead'),
              ),
              if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Semantics(liveRegion: true, child: Text(_status!)),
                ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () async => context.global.dispatchAsync(StartSmartScan()),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry local discovery'),
              ),
              TextButton(onPressed: () async => context.push(() => const TroubleshootPage()), child: const Text('Connection troubleshooting')),
              const Text(
                'Guest Wi-Fi, client isolation, VPN routes and firewalls can block discovery. Allow the configured TCP/UDP port on a trusted private network. QuickDrop never switches to an internet relay automatically.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
