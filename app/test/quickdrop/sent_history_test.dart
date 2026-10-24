import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/quickdrop/sent_history.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _Persistence extends Fake implements PersistenceService {
  bool enabled = true;
  List<String> stored = [];
  Duration delay = Duration.zero;
  @override
  bool isSaveToHistory() => enabled;
  @override
  List<String> getQuickDropSentHistory() => stored;
  @override
  Future<void> setQuickDropSentHistory(List<String> entries) async {
    await Future<void>.delayed(delay);
    stored = entries;
  }
}

SendSessionState session(SessionStatus status, {bool message = false}) => SendSessionState(
  sessionId: 'session',
  remoteSessionId: null,
  background: true,
  status: status,
  target: Device.empty.copyWith(alias: 'My laptop'),
  files: {
    'file': SendingFile(
      file: FileDto(id: 'file', fileName: 'photo.jpg', size: 128, fileType: FileType.image, hash: null, preview: null, metadata: null),
      token: 'never persist this token',
      thumbnail: null,
      asset: null,
      path: '/photos/photo.jpg',
      bytes: message ? [1, 2, 3] : null,
      errorMessage: null,
    ),
  },
  hashedFileCount: 1,
  startTime: 1000,
  endTime: status == SessionStatus.finished ? 2000 : null,
  sendingTasks: [],
  errorMessage: null,
);

void main() {
  test('updates one record per session/file and never stores transfer tokens or file bytes', () async {
    final persistence = _Persistence();
    final service = ReduxNotifier.test(redux: SentHistoryService(persistence));
    await service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.waiting)));
    await service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.finished)));
    expect(service.state, hasLength(1));
    expect(service.state.single.status, 'finished');
    expect(persistence.stored.join(), isNot(contains('never persist this token')));
    final reopened = ReduxNotifier.test(redux: SentHistoryService(persistence));
    expect(reopened.state.single.name, 'photo.jpg');
    await reopened.dispatchAsync(ClearSentHistoryAction());
    expect(persistence.stored, isEmpty);
  });
  test('concurrent recipients and clearing cannot restore stale records', () async {
    final persistence = _Persistence()..delay = const Duration(milliseconds: 10);
    final service = ReduxNotifier.test(redux: SentHistoryService(persistence));
    await Future.wait([
      service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.finished))),
      service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.finished).copyWith(sessionId: 'second'))),
    ]);
    expect(service.state, hasLength(2));
    await Future.wait([
      service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.finished).copyWith(sessionId: 'third'))),
      service.dispatchAsync(ClearSentHistoryAction()),
    ]);
    expect(service.state, isEmpty);
    expect(persistence.stored, isEmpty);
  });
  test('honors disabled history and excludes in-memory text messages', () async {
    final persistence = _Persistence();
    final service = ReduxNotifier.test(redux: SentHistoryService(persistence));
    persistence.enabled = false;
    await service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.finished)));
    expect(service.state, isEmpty);
    persistence.enabled = true;
    await service.dispatchAsync(RecordSentSessionAction(session(SessionStatus.finished, message: true)));
    expect(service.state, isEmpty);
    expect(persistence.stored, isEmpty);
  });
}
