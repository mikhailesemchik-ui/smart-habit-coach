import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  });

  Future<void> openProfileTab(WidgetTester tester) async {
    await tester.pumpWidget(const SmartHabitCoachApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
  }

  testWidgets('Profile screen shows the saved display name', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'app_settings':
          '{"displayName": "Jamie", "themeMode": "system", "startOfWeek": "monday"}',
    });

    await openProfileTab(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('profileDisplayName'))).data,
      'Jamie',
    );
  });

  testWidgets(
    'Profile screen shows the default display name when none is saved',
    (tester) async {
      await openProfileTab(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('profileDisplayName'))).data,
        'User',
      );
    },
  );

  testWidgets('Selecting Dark theme applies it to the app immediately', (
    tester,
  ) async {
    await openProfileTab(tester);

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('Editing the display name updates it across the screen', (
    tester,
  ) async {
    await openProfileTab(tester);

    await tester.enterText(find.byType(TextField), 'Morgan');
    await tester.pumpAndSettle();

    expect(find.text('Morgan'), findsWidgets);
  });

  testWidgets(
    'Theme selector shows System, Light, and Dark without wrapping on a narrow screen',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;

      await openProfileTab(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Labels must not wrap onto a second line: a wrapped two-line label
      // would roughly double this single-line text's rendered height.
      final singleLineHeight = tester.getSize(find.text('Light')).height;
      for (final label in ['System', 'Light', 'Dark']) {
        expect(tester.getSize(find.text(label)).height, singleLineHeight);
      }

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    },
  );
}
