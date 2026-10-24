import 'package:flutter/material.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quickdrop/quicklink_page.dart';
import 'package:localsend_app/quickdrop/quickpair_page.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class QuickDropSendHeader extends StatelessWidget {
  const QuickDropSendHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final multi = context.watch(settingsProvider.select((s) => s.sendMode == SendMode.multiple));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFF1769FF), Color(0xFF164BC0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                'QUICKDROP',
                style: TextStyle(color: Colors.white70, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Good things\nare better shared.',
            style: TextStyle(color: Colors.white, fontSize: 34, height: 1.1, letterSpacing: -1.2, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('Choose your files. Find your device. Drop.', style: TextStyle(color: Colors.white70, height: 1.5)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Action(label: 'QuickPair', icon: Icons.qr_code, onTap: () async => context.push(() => const QuickPairPage())),
              _Action(
                label: multi ? 'MultiDrop · On' : 'MultiDrop',
                icon: Icons.devices,
                selected: multi,
                onTap: () async => context.notifier(settingsProvider).setSendMode(multi ? SendMode.single : SendMode.multiple),
              ),
              _Action(label: 'QuickLink', icon: Icons.public, onTap: () async => context.push(() => const QuickLinkPage())),
            ],
          ),
          if (multi)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Tap each recipient below to send the same selection. Each transfer has its own status and cancel control.',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  const _Action({required this.label, required this.icon, required this.onTap, this.selected = false});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: selected ? Colors.white.withValues(alpha: .22) : Colors.white.withValues(alpha: .08),
      side: BorderSide(color: Colors.white.withValues(alpha: .3)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label),
  );
}
