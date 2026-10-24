import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('Refena');

class CustomRefenaObserver extends RefenaMultiObserver {
  CustomRefenaObserver()
    : super(
        observers: [
          RefenaDebugObserver(
            // Provider states may contain file metadata, previews and session tokens.
            // Never emit their serialized values, including in development logs.
            onLine: (_) => _logger.fine('Application state changed'),
            exclude: _exclude,
          ),
        ],
      );
}

bool _exclude(RefenaEvent event) {
  return switch (event) {
    ChangeEvent() => event.notifier is DiscoveryLogger || event.notifier is LocalIpService || event.notifier is FileTransferNotifier,
    ActionDispatchedEvent() => event.action.runtimeType.toString() == '_FetchLocalIpAction',
    ActionFinishedEvent() => event.action.runtimeType.toString() == '_FetchLocalIpAction',
    _ => false,
  };
}
