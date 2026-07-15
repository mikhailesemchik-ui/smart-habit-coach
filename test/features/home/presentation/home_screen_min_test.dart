import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/date_key.dart';
import 'package:smart_habit_coach/features/home/presentation/home_screen.dart';

import '../../../support/test_namespace.dart';

const _habitsKey = 'habits:$testNamespaceUid';

Map<String, dynamic> _baseJson({
  String id = '1',
  String title = 'Yoga',
  String? minimumVersion,
  List<String> completedDates = const [],
  List<String> minimumCompletedDates = const [],
}) => {
  'id': id,
  'title': title,
  'scheduledTime': '08:00 AM',
  'iconId': 'fitness',
  'weekdays': [1, 2, 3, 4, 5, 6, 7],
  'completedDates': completedDates,
  'minimumCompletedDates': minimumCompletedDates,
  'minimumVersion': ?minimumVersion,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Test 9: habit without minimum version keeps binary Today behavior ───────
  testWidgets(
    'habit without minimumVersion toggles directly to full without sheet',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        _habitsKey: jsonEncode([_baseJson()]),
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      // Tap the unchecked icon → should go directly to full, no picker sheet.
      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.circle), findsOneWidget);
      // No picker sheet opened.
      expect(find.text('Complete fully'), findsNothing);
    },
  );

  // ── Test 10: habit with minimum version opens three-state control ────────────
  testWidgets('habit with minimumVersion opens three-state picker sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([_baseJson(minimumVersion: 'Light stretch')]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();

    // Picker sheet must be visible with all three options.
    expect(find.text('Complete fully'), findsOneWidget);
    expect(find.text('Minimum done'), findsOneWidget);
    expect(find.text('Not completed'), findsOneWidget);
  });

  // ── Test 11: Today displays full state correctly ─────────────────────────────
  testWidgets('habit completed fully shows check_circle icon', (tester) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(minimumVersion: 'Light stretch', completedDates: [today]),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(find.byIcon(Icons.adjust), findsNothing);
  });

  // ── Test 12: Today displays minimum state correctly ──────────────────────────
  testWidgets('habit at minimum shows adjust icon and subtitle text', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(
          minimumVersion: 'Light stretch',
          minimumCompletedDates: [today],
        ),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.adjust), findsOneWidget);
    expect(find.textContaining('Minimum done'), findsOneWidget);
  });

  // ── Test 13: Today progress counts full but not minimum ─────────────────────
  testWidgets('progress bar counts full completions, not minimum', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        // minimum state → should NOT count toward progress
        _baseJson(
          id: '1',
          title: 'Yoga',
          minimumVersion: 'Light stretch',
          minimumCompletedDates: [today],
        ),
        // no completion → should NOT count
        _baseJson(id: '2', title: 'Run'),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Minimum done: progress count should be 0 complete, 1 partial, 1 remaining.
    expect(find.text('0 complete · 1 partial · 1 remaining'), findsOneWidget);
    // Weighted score: (0 + 0.5*1)/2 = 25%
    expect(find.text('25% progress score'), findsOneWidget);
  });

  // ── Tests 1-5: weighted Today progress ──────────────────────────────────────

  // Test 1: one minimum completion changes Today progress from zero
  testWidgets('one minimum completion raises progress score above zero', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(
          minimumVersion: 'Light stretch',
          minimumCompletedDates: [today],
        ),
        _baseJson(id: '2', title: 'Run'),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Score = (0 + 0.5*1)/2 = 25% — not zero.
    expect(find.text('25% progress score'), findsOneWidget);
  });

  // Test 2: weighted Today score uses minimum = 0.5
  testWidgets('weighted score assigns 0.5 weight to minimum completions', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(
          id: '1',
          minimumVersion: 'Light',
          minimumCompletedDates: [today],
        ),
        _baseJson(id: '2', title: 'Run'),
        _baseJson(id: '3', title: 'Walk'),
        _baseJson(id: '4', title: 'Meditate'),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Score = (0 + 0.5*1)/4 = 12.5% → rounds to 13%.
    expect(find.text('13% progress score'), findsOneWidget);
  });

  // Test 3: Today label distinguishes full and minimum
  testWidgets('Today label shows full and minimum as separate counts', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(
          id: '1',
          minimumVersion: 'Light',
          minimumCompletedDates: [today],
        ),
        _baseJson(id: '2', title: 'Run', completedDates: [today]),
        _baseJson(id: '3', title: 'Walk'),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('1 complete · 1 partial · 1 remaining'), findsOneWidget);
  });

  // Test 4: full completion still counts as 1.0
  testWidgets('full completion scores 1.0 in progress calculation', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(id: '1', completedDates: [today]),
        _baseJson(id: '2', title: 'Run'),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Score = 1/2 = 50%.
    expect(find.text('1 complete · 1 remaining'), findsOneWidget);
    expect(find.text('50% progress score'), findsOneWidget);
  });

  // Test 5: mixed full/minimum progress is correct
  testWidgets('mixed full and minimum gives correct weighted score', (
    tester,
  ) async {
    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(id: '1', completedDates: [today]),
        _baseJson(
          id: '2',
          title: 'Run',
          minimumVersion: 'Light jog',
          minimumCompletedDates: [today],
        ),
        _baseJson(id: '3', title: 'Walk'),
        _baseJson(id: '4', title: 'Meditate'),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Score = (1 + 0.5*1)/4 = 1.5/4 = 37.5% → rounds to 38%.
    expect(find.text('1 complete · 1 partial · 2 remaining'), findsOneWidget);
    expect(find.text('38% progress score'), findsOneWidget);
  });

  // ── Test 17: compact-screen UI does not overflow ──────────────────────────
  // Test 24: compact-screen UI does not overflow ─────────────────────────────
  testWidgets('min-version habit card does not overflow on compact screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    final today = todayKey();
    SharedPreferences.setMockInitialValues({
      _habitsKey: jsonEncode([
        _baseJson(
          minimumVersion: 'Light stretch',
          minimumCompletedDates: [today],
        ),
      ]),
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.adjust), findsOneWidget);
  });
}
