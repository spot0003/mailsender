import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickDropOnboarding extends StatefulWidget {
  const QuickDropOnboarding({super.key});
  @override
  State<QuickDropOnboarding> createState() => _QuickDropOnboardingState();
}

class _QuickDropOnboardingState extends State<QuickDropOnboarding> {
  int _index = 0;
  static const _pages = [
    (
      Icons.devices_rounded,
      'Everything.\nA little closer.',
      'Send between your phone and computer over the same network. No account, no internet, no detours.',
    ),
    (
      Icons.shield_outlined,
      'Your files.\nYour call.',
      'Review incoming requests, keep HTTPS enabled, and choose where files arrive. QuickVault protects separately imported copies with your PIN.',
    ),
    (
      Icons.public_rounded,
      'Go further.\nOn your terms.',
      'QuickLink is an optional internet mode using your chosen HTTPS relay. It needs a deployed server and explicit consent. Local transfers never switch to it automatically.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('qd_onboarded', true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    final color = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to QuickDrop'),
        actions: [TextButton(onPressed: _finish, child: const Text('Skip'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height < 700 ? 160 : 240,
                        child: FittedBox(
                          child: SizedBox(
                            width: 300,
                            height: 240,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 230,
                                  height: 230,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .04)),
                                ),
                                Container(
                                  width: 170,
                                  height: 170,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color.withValues(alpha: .18)),
                                  ),
                                ),
                                Transform.rotate(
                                  angle: -.1,
                                  child: Container(
                                    width: 110,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(28),
                                      boxShadow: [BoxShadow(color: color.withValues(alpha: .22), blurRadius: 36, offset: const Offset(0, 18))],
                                    ),
                                    child: Icon(page.$1, size: 58, color: Colors.white),
                                  ),
                                ),
                                Positioned(
                                  right: 48,
                                  bottom: 36,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
                                    child: Icon(Icons.north_east_rounded, color: color, size: 32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 240),
                        child: Column(
                          key: ValueKey(_index),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              page.$2,
                              style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.5),
                            ),
                            const SizedBox(height: 20),
                            Text(page.$3, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 36),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (i) => Container(
                            width: i == _index ? 28 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: i == _index ? color : color.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () async {
                          if (_index == _pages.length - 1) {
                            await _finish();
                          } else {
                            setState(() => _index++);
                          }
                        },
                        child: Text(_index == 2 ? 'Make your first drop' : 'Continue'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
