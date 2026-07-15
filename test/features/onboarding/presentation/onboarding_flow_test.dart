import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/app.dart';

void main() {
  testWidgets('First launch shows onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    expect(find.text('Build better habits'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('Completing onboarding saves state and opens the main app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text('Get smart suggestions'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('Today')),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('Skip saves state and opens the main app', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('Today')),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('Returning user opens the main app directly', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});

    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    expect(find.text('Build better habits'), findsNothing);
    expect(
      find.descendant(of: find.byType(ListView), matching: find.text('Today')),
      findsOneWidget,
    );
  });

  testWidgets('Back button returns to the previous page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(SmartHabitCoachApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Back'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text('Track your progress'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();

    expect(find.text('Build better habits'), findsOneWidget);
  });
}
