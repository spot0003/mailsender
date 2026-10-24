import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quickdrop/resend_file.dart';
import 'package:localsend_app/quickdrop/sent_history.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/file_info_dialog.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:path/path.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _EntryOption {
  open,
  resend,
  showInFolder,
  info,
  delete
  ;

  String get label {
    return switch (this) {
      _EntryOption.resend => 'Resend',
      _EntryOption.open => t.receiveHistoryPage.entryActions.open,
      _EntryOption.showInFolder => t.receiveHistoryPage.entryActions.showInFolder,
      _EntryOption.info => t.receiveHistoryPage.entryActions.info,
      _EntryOption.delete => t.receiveHistoryPage.entryActions.deleteFromHistory,
    };
  }
}

const _optionsAll = _EntryOption.values;
final _optionsWithoutOpen = [_EntryOption.info, _EntryOption.delete];

class ReceiveHistoryPage extends StatefulWidget {
  const ReceiveHistoryPage({super.key});
  @override
  State<ReceiveHistoryPage> createState() => _ReceiveHistoryPageState();
}

class _ReceiveHistoryPageState extends State<ReceiveHistoryPage> {
  String _query = '';

  Future<void> _openFile(
    BuildContext context,
    ReceiveHistoryEntry entry,
    Dispatcher<ReceiveHistoryService, List<ReceiveHistoryEntry>> dispatcher,
  ) async {
    if (entry.path != null) {
      await openFile(
        context,
        entry.fileType,
        entry.path!,
        onDeleteTap: () => dispatcher.dispatchAsync(RemoveHistoryEntryAction(entry.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = context.watch(receiveHistoryProvider);
    final entries = allEntries.where((e) => '${e.isMessage ? 'Message' : e.fileName} ${e.senderAlias}'.toLowerCase().contains(_query)).toList();
    final sent = context.watch(sentHistoryProvider).where((e) => '${e.name} ${e.recipient} ${e.status}'.toLowerCase().contains(_query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart History'),
      ),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search names, recipients, or status'),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Sent', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear sent history?'),
                        content: const Text('Files are not deleted.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) await context.redux(sentHistoryProvider).dispatchAsync(ClearSentHistoryAction());
                  },
                  child: const Text('Clear sent history'),
                ),
              ],
            ),
          ),
          if (sent.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No matching sent transfers.')),
          ...sent.map(
            (entry) => ListTile(
              leading: const Icon(Icons.north_east),
              title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${entry.recipient} · ${entry.size.asReadableFileSize} · ${entry.status}\n${entry.date.toLocal()}'),
              isThreeLine: true,
              trailing: entry.path == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.send_outlined),
                      tooltip: 'Resend',
                      onPressed: () async => resendHistoryFile(context, filePath: entry.path!, name: entry.name, size: entry.size, type: entry.type),
                    ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Received', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 15),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainerIfDark,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainerIfDark,
                  ),
                  onPressed: checkPlatform([TargetPlatform.iOS])
                      ? null
                      : () async {
                          // ignore: use_build_context_synchronously
                          final destination = context.read(settingsProvider).destination ?? await getDefaultDestinationDirectory();
                          await openFolder(folderPath: destination);
                        },
                  icon: const Icon(Icons.folder),
                  label: Text(t.receiveHistoryPage.openFolder),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainerIfDark,
                    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainerIfDark,
                  ),
                  onPressed: allEntries.isEmpty
                      ? null
                      : () async {
                          final result = await showDialog(
                            context: context,
                            builder: (_) => const HistoryClearDialog(),
                          );

                          if (context.mounted && result == true) {
                            await context.redux(receiveHistoryProvider).dispatchAsync(RemoveAllHistoryEntriesAction());
                          }
                        },
                  icon: const Icon(Icons.delete),
                  label: Text(t.receiveHistoryPage.deleteHistory),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 100),
              child: Center(child: Text(t.receiveHistoryPage.empty, style: Theme.of(context).textTheme.headlineMedium)),
            )
          else
            ...entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                child: InkWell(
                  splashColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: entry.path != null || entry.isMessage
                      ? () async {
                          if (entry.isMessage) {
                            final vm = ViewProvider((ref) {
                              return ReceivePageVm(
                                status: SessionStatus.waiting,
                                sender: Device(
                                  signalingId: null,
                                  ip: '0.0.0.0',
                                  version: '1.0.0',
                                  port: 8080,
                                  https: false,
                                  fingerprint: 'fingerprint',
                                  alias: entry.senderAlias,
                                  deviceModel: 'deviceModel',
                                  deviceType: DeviceType.web,
                                  download: true,
                                  channels: const [],
                                ),
                                showSenderInfo: false,
                                files: [],
                                message: entry.fileName,
                                onAccept: () {},
                                onDecline: () {},
                                onClose: () {},
                              );
                            });

                            // ignore: unawaited_futures
                            context.push(() => ReceivePage(vm));
                            return;
                          }

                          await _openFile(context, entry, context.redux(receiveHistoryProvider));
                        }
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FilePathThumbnail(
                        path: entry.path,
                        fileType: entry.fileType,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 3),
                            Text(
                              entry.isMessage ? 'Message' : entry.fileName,
                              style: const TextStyle(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                            Text(
                              '${entry.timestampString(context)} - ${entry.fileSize.asReadableFileSize} - ${entry.senderAlias}',
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      PopupMenuButton<_EntryOption>(
                        onSelected: (_EntryOption item) async {
                          switch (item) {
                            case _EntryOption.resend:
                              if (entry.path != null && !entry.isMessage) {
                                await resendHistoryFile(
                                  context,
                                  filePath: entry.path!,
                                  name: entry.fileName,
                                  size: entry.fileSize,
                                  type: entry.fileType,
                                );
                              }
                              break;
                            case _EntryOption.open:
                              await _openFile(context, entry, context.redux(receiveHistoryProvider));
                              break;
                            case _EntryOption.showInFolder:
                              if (entry.path != null) {
                                await openFolder(
                                  folderPath: File(entry.path!).parent.path,
                                  fileName: path.basename(entry.path!),
                                );
                              }
                              break;
                            case _EntryOption.info:
                              // ignore: use_build_context_synchronously
                              await showDialog(
                                context: context,
                                builder: (_) => FileInfoDialog(entry: entry),
                              );
                              break;
                            case _EntryOption.delete:
                              // ignore: use_build_context_synchronously
                              await context.redux(receiveHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(entry.id));
                              break;
                          }
                        },
                        itemBuilder: (BuildContext context) {
                          return (entry.path != null ? _optionsAll.where((e) => e != _EntryOption.resend || !entry.isMessage) : _optionsWithoutOpen)
                              .map((e) {
                                return PopupMenuItem<_EntryOption>(
                                  value: e,
                                  child: Text(e.label),
                                );
                              })
                              .toList();
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
