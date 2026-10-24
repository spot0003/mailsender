import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/quickdrop/onboarding_page.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(1440, 900)]) {
      testWidgets('QuickDrop introduction fits $brightness at $size with accessible text scaling', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: getTheme(ColorMode.localsend, const Color(0xFF1769FF), brightness, null),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const QuickDropOnboarding(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Everything.\nA little closer.'), findsOneWidget);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Your files.\nYour call.'), findsOneWidget);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Go further.\nOn your terms.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
