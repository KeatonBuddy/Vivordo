import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/personal_profile_screen.dart';
import 'package:vivordo_health/src/services/personal_profile_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'measurement date and optional body fat (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        (double, double, double?, DateTime)? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? VivordoTheme.dark : VivordoTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result =
                        await showModalBottomSheet<
                          (double, double, double?, DateTime)
                        >(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => const MeasurementEditorSheet(
                            title: 'Add Measurement',
                            profile: PersonalProfile(
                              heightCm: 182.88,
                              weightKg: 70,
                            ),
                          ),
                        );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Optional'), findsOneWidget);
        await tester.tap(find.text('Date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1').last);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save Measurement'));
        await tester.tap(find.text('Save Measurement'));
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.$1, closeTo(182.88, .01));
        expect(result!.$3, isNull);
        expect(result!.$4.day, 1);
        expect(result!.$4.month, DateTime.now().month);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('invalid body fat does not silently save as omitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const MeasurementEditorSheet(
            title: 'Add Measurement',
            profile: PersonalProfile(heightCm: 180, weightKg: 70),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'invalid');
    await tester.ensureVisible(find.text('Save Measurement'));
    await tester.tap(find.text('Save Measurement'));
    await tester.pump();
    expect(find.textContaining('Enter a valid height'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
