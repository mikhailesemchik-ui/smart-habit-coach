import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/coach/presentation/coach_insights_screen.dart';
import 'package:smart_habit_coach/features/progress/presentation/progress_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Coach Insights entry point appears in Progress', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coach Insights'), findsOneWidget);
  });

  testWidgets('tapping the entry point opens Coach Insights', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProgressScreen()));
    await tester.pumpAndSettle();

    final entry = find.text('Coach Insights');

    await tester.ensureVisible(entry);
    await tester.pump();

    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(CoachInsightsScreen), findsOneWidget);
  });
}
