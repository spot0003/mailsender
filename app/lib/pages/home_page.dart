import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/quickdrop/onboarding_page.dart';
import 'package:localsend_app/quickdrop/quicklink_page.dart';
import 'package:localsend_app/quickdrop/quickpair_page.dart';
import 'package:localsend_app/quickdrop/vault_page.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HomeTab {
  receive(Icons.wifi),
  send(Icons.send),
  settings(Icons.settings)
  ;

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.receive:
        return t.receiveTab.title;
      case HomeTab.send:
        return t.sendTab.title;
      case HomeTab.settings:
        return t.settingsTab.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
      if (widget.appStart) {
        final prefs = await SharedPreferences.getInstance();
        if (mounted && prefs.getBool('qd_onboarded') != true) {
          await context.push(() => const QuickDropOnboarding());
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        // the drop may contain a mix of files and directories
        final droppedDirectories = event.files.where((file) => Directory(file.path).existsSync()).toList();
        final droppedFiles = event.files.where((file) => !Directory(file.path).existsSync()).toList();

        for (final directory in droppedDirectories) {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory.path));
        }

        if (droppedFiles.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: droppedFiles,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.send);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          return Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/img/logo-128.png', width: 30, height: 30),
                  const SizedBox(width: 10),
                  const Text('QuickDrop', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.5)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'QuickPair',
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: () async => context.push(() => const QuickPairPage()),
                ),
                PopupMenuButton<String>(
                  tooltip: 'QuickDrop tools',
                  onSelected: (tool) async {
                    final Widget page = switch (tool) {
                      'vault' => const VaultPage(),
                      'history' => const ReceiveHistoryPage(),
                      'remote' => const QuickLinkPage(),
                      _ => const QuickDropOnboarding(),
                    };
                    await context.push(() => page);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'history', child: Text('Smart History')),
                    PopupMenuItem(value: 'vault', child: Text('QuickVault')),
                    PopupMenuItem(value: 'remote', child: Text('QuickLink · Internet')),
                    PopupMenuItem(value: 'guide', child: Text('QuickDrop guide')),
                  ],
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Row(
              children: [
                if (!sizingInformation.isMobile)
                  NavigationRail(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    extended: sizingInformation.isDesktop,
                    backgroundColor: Theme.of(context).cardColorWithElevation,
                    leading: sizingInformation.isDesktop
                        ? const Column(
                            children: [
                              SizedBox(height: 20),
                              Text(
                                'QuickDrop',
                                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 20),
                            ],
                          )
                        : null,
                    destinations: HomeTab.values.map((tab) {
                      return NavigationRailDestination(
                        icon: Icon(tab.icon),
                        label: Text(tab.label),
                      );
                    }).toList(),
                  ),
                Expanded(
                  child: SafeArea(
                    left: sizingInformation.isMobile,
                    child: Stack(
                      children: [
                        PageView(
                          controller: vm.controller,
                          physics: const NeverScrollableScrollPhysics(),
                          children: const [
                            ReceiveTab(),
                            SendTab(),
                            SettingsTab(),
                          ],
                        ),
                        if (_dragAndDropIndicator)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.file_download, size: 128),
                                const SizedBox(height: 30),
                                Text(t.sendTab.placeItems, style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: sizingInformation.isMobile
                ? NavigationBar(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationDestination(icon: Icon(tab.icon), label: tab.label);
                    }).toList(),
                  )
                : null,
          );
        },
      ),
    );
  }
}
