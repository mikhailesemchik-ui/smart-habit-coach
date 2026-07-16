import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/features/home/domain/habit.dart';
import 'package:smart_habit_coach/features/home/presentation/add_habit_sheet.dart';

Widget _sheet({Habit? initialHabit}) {
  return MaterialApp(
    home: Scaffold(body: AddHabitSheet(initialHabit: initialHabit)),
  );
}

Future<void> _pumpQuantitativeForm(WidgetTester tester) async {
  // Switch to Amount tracking
  await tester.tap(find.text('Amount'));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Test: Unit selector shows preset options
  testWidgets('unit dropdown shows preset options', (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.pumpAndSettle();

    await _pumpQuantitativeForm(tester);
    await tester.pumpAndSettle();

    // Open dropdown
    await tester.ensureVisible(find.text('min'));
    await tester.tap(find.text('min'));
    await tester.pumpAndSettle();

    // Preset options are visible in the dropdown menu
    expect(find.text('hours'), findsWidgets);
    expect(find.text('steps'), findsWidgets);
    expect(find.text('L'), findsWidgets);
    expect(find.text('Custom'), findsWidgets);
  });

  // Test: selecting a preset saves that unit
  testWidgets('selecting "L" preset stores "L" as unit', (tester) async {
    Habit? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                saved = await showModalBottomSheet<Habit>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const AddHabitSheet(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit title'),
      'Drink water',
    );

    await _pumpQuantitativeForm(tester);
    await tester.pumpAndSettle();

    // Enter target
    await tester.enterText(find.byKey(dailyTargetFieldKey), '3');

    // Select 'L' in the dropdown (it's already showing 'min' as first preset)
    await tester.ensureVisible(find.text('min'));
    await tester.tap(find.text('min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('L').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saved?.unit, 'L');
  });

  // Test: Custom mode via a habit with a custom unit shows the text field
  testWidgets('Custom mode shows custom unit text field', (tester) async {
    // Open the sheet in edit mode with a custom unit — this puts it straight
    // into Custom mode without needing to interact with the dropdown.
    final existing = Habit(
      id: '1',
      title: 'Meditate',
      scheduledTime: '07:00 AM',
      icon: Icons.self_improvement_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 10,
      unit: 'sessions', // not in presets → Custom mode
    );

    await tester.pumpWidget(_sheet(initialHabit: existing));
    await tester.pumpAndSettle();

    // Custom unit text field is visible with the existing value
    expect(find.byKey(customUnitFieldKey), findsOneWidget);
    expect(find.text('sessions'), findsWidgets);
  });

  // Test: Preset mode shows no custom unit text field
  testWidgets('preset mode shows no custom unit text field', (tester) async {
    await tester.pumpWidget(_sheet());
    await tester.pumpAndSettle();

    await _pumpQuantitativeForm(tester);
    await tester.pumpAndSettle();

    // With 'min' selected (default preset), no custom unit field
    expect(find.byKey(customUnitFieldKey), findsNothing);
  });

  // Test: existing preset unit loads in preset selection
  testWidgets('editing a habit with preset unit shows that preset selected', (
    tester,
  ) async {
    final existing = Habit(
      id: '1',
      title: 'Walk',
      scheduledTime: '08:00 AM',
      icon: Icons.directions_walk_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 5000,
      unit: 'steps',
    );

    await tester.pumpWidget(_sheet(initialHabit: existing));
    await tester.pumpAndSettle();

    // The 'steps' preset should be shown as the current value
    expect(find.text('steps'), findsWidgets);
    // No custom unit field visible
    expect(find.byKey(customUnitFieldKey), findsNothing);
  });

  // Test: existing custom unit loads in Custom mode with text filled
  testWidgets('editing a habit with custom unit shows Custom mode with text', (
    tester,
  ) async {
    final existing = Habit(
      id: '1',
      title: 'Meditate',
      scheduledTime: '07:00 AM',
      icon: Icons.self_improvement_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 10,
      unit: 'sessions',
    );

    await tester.pumpWidget(_sheet(initialHabit: existing));
    await tester.pumpAndSettle();

    // Custom unit field appears with pre-filled value
    expect(find.byKey(customUnitFieldKey), findsOneWidget);
    expect(find.text('sessions'), findsWidgets);
  });

  // Test: unit selector does not overflow on a narrow screen
  testWidgets('unit selector does not overflow on a narrow screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(_sheet());
    await tester.pumpAndSettle();

    await _pumpQuantitativeForm(tester);
    await tester.pumpAndSettle();

    // DropdownButtonFormField is visible; isExpanded: true prevents overflow.
    expect(find.text('min'), findsOneWidget);
    // No exception == no overflow error.
  });

  // Test: long preset units ('hours', 'steps', 'pages') remain usable on narrow screen
  testWidgets('long preset units remain usable on narrow screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;

    final existing = Habit(
      id: '1',
      title: 'Run',
      scheduledTime: '07:00 AM',
      icon: Icons.directions_run_outlined,
      trackingType: HabitTrackingType.quantitative,
      targetValue: 10000,
      unit: 'steps',
    );

    await tester.pumpWidget(_sheet(initialHabit: existing));
    await tester.pumpAndSettle();

    // 'steps' is visible as the selected value without overflow.
    expect(find.text('steps'), findsWidgets);
  });
}
