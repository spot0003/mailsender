import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

Future<void> resendHistoryFile(
  BuildContext context, {
  required String filePath,
  required String name,
  required int size,
  required FileType type,
}) async {
  if (!filePath.startsWith('content://') && !await File(filePath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The original file is no longer available. Select it again in Send.')));
    }
    return;
  }
  if (!context.mounted) return;
  await context
      .redux(selectedSendingFilesProvider)
      .dispatchAsync(
        AddFilesAction<CrossFile>(
          files: [
            CrossFile(
              name: name,
              fileType: type,
              size: size,
              thumbnail: null,
              asset: null,
              path: filePath,
              bytes: null,
              lastModified: null,
              lastAccessed: null,
            ),
          ],
          converter: (file) async => file,
        ),
      );
  if (!context.mounted) return;
  context.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
  Navigator.of(context).popUntil((route) => route.isFirst);
}
