import 'dart:convert';

import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

class SentHistoryEntry {
  final String id;
  final String name;
  final String recipient;
  final String status;
  final String? path;
  final int size;
  final FileType type;
  final DateTime date;
  const SentHistoryEntry({
    required this.id,
    required this.name,
    required this.recipient,
    required this.status,
    required this.path,
    required this.size,
    required this.type,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'recipient': recipient,
    'status': status,
    'path': path,
    'size': size,
    'type': type.name,
    'date': date.toUtc().toIso8601String(),
  };
  static SentHistoryEntry fromJson(Map<String, dynamic> json) => SentHistoryEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    recipient: json['recipient'] as String,
    status: json['status'] as String,
    path: json['path'] as String?,
    size: json['size'] as int,
    type: FileType.values.firstWhere((v) => v.name == json['type'], orElse: () => FileType.other),
    date: DateTime.parse(json['date'] as String),
  );
}

final sentHistoryProvider = ReduxProvider<SentHistoryService, List<SentHistoryEntry>>((ref) => SentHistoryService(ref.read(persistenceProvider)));

class SentHistoryService extends ReduxNotifier<List<SentHistoryEntry>> {
  final PersistenceService persistence;
  SentHistoryService(this.persistence);
  List<SentHistoryEntry>? _latest;
  Future<void> _writes = Future.value();
  List<SentHistoryEntry> get records => _latest ?? state;

  Future<List<SentHistoryEntry>> save(List<SentHistoryEntry> next) {
    _latest = next;
    final snapshot = next.map((r) => jsonEncode(r.toJson())).toList();
    _writes = _writes.then((_) => persistence.setQuickDropSentHistory(snapshot)).catchError((Object _) {
      Logger('QuickDropHistory').warning('Unable to persist transfer history.');
    });
    // Concurrent recipients and a clear operation must never restore an older snapshot.
    return _writes.then((_) => _latest!);
  }

  @override
  List<SentHistoryEntry> init() {
    try {
      return persistence.getQuickDropSentHistory().map((entry) => SentHistoryEntry.fromJson(jsonDecode(entry) as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    } // malformed local records must not prevent app startup
  }
}

class RecordSentSessionAction extends AsyncReduxAction<SentHistoryService, List<SentHistoryEntry>> {
  final SendSessionState session;
  RecordSentSessionAction(this.session);
  @override
  Future<List<SentHistoryEntry>> reduce() async {
    if (!notifier.persistence.isSaveToHistory()) return state;
    final records = session.files.entries
        .where((e) => e.value.bytes == null)
        .map(
          (e) => SentHistoryEntry(
            id: '${session.sessionId}:${e.key}',
            name: e.value.file.fileName,
            recipient: session.target.alias,
            status: session.status.name,
            path: e.value.path,
            size: e.value.file.size,
            type: e.value.file.fileType,
            date: DateTime.fromMillisecondsSinceEpoch(session.endTime ?? session.startTime ?? DateTime.now().millisecondsSinceEpoch),
          ),
        )
        .toList();
    final ids = records.map((r) => r.id).toSet();
    final next = [...records, ...notifier.records.where((entry) => !ids.contains(entry.id))].take(200).toList();
    return notifier.save(next);
  }
}

class ClearSentHistoryAction extends AsyncReduxAction<SentHistoryService, List<SentHistoryEntry>> {
  @override
  Future<List<SentHistoryEntry>> reduce() async {
    return notifier.save([]);
  }
}
