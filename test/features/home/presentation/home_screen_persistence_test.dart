import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

void main() {
  group('HomeScreen persistence', () {
    testWidgets(
      'editing title and time does not erase existing completion dates',
      (tester) async {
        final today = todayKey();
        SharedPreferences.setMockInitialValues({
          'habits': jsonEncode([
            {
              'id': '1',
              'title': 'Drink water',
              'scheduledTime': '08:00 AM',
              'iconId': 'water',
              'completedDates': [today],
            },
          ]),
        });

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Drink water'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Habit title'),
          'Drink more water',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        final loaded = await HabitStorage().loadHabits();

        expect(loaded, isNotNull);
        expect(loaded!.first.title, 'Drink more water');
        expect(loaded.first.completedDates, contains(today));
        expect(loaded.first.isCompletedToday, isTrue);
      },
    );

    testWidgets(
      'completion history survives widget recreation via mocked SharedPreferences',
      (tester) async {
        SharedPreferences.setMockInitialValues({});

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
        await tester.pump();

        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        // Force a fresh HomeScreen state (simulates re-navigating or hot restart).
        await tester.pumpWidget(
          const MaterialApp(home: HomeScreen(key: ValueKey('reload'))),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check_circle), findsOneWidget);
      },
    );
  });
}
