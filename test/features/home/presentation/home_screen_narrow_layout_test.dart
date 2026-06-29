import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/presentation/habit_details_screen.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Add habit sheet keeps the Save button above the system navigation inset',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 48);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final saveButtonBottom = tester
          .getRect(find.widgetWithText(FilledButton, 'Save'))
          .bottom;
      expect(saveButtonBottom, lessThanOrEqualTo(640 - 48));
    },
  );

  testWidgets(
    'Add habit sheet does not overflow when the keyboard covers most of a short screen',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    },
  );

  testWidgets(
    'Habit details screen does not overflow on a compact screen with system insets',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 48);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Drink water'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HabitDetailsScreen), findsOneWidget);
    },
  );
}
