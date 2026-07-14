import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_resolver.dart';
import 'package:smart_habit_coach/features/home/data/habit_storage.dart';
import 'package:smart_habit_coach/features/privacy/data/local_data_export_service.dart';
import 'package:smart_habit_coach/features/privacy/domain/export_result.dart';
import 'package:smart_habit_coach/features/privacy/domain/local_data_export.dart';
import 'package:smart_habit_coach/features/privacy/presentation/privacy_keys.dart';
import 'package:smart_habit_coach/features/privacy/presentation/privacy_screen.dart';

import '../../../support/test_namespace.dart';

/// Lets a test control exactly when [export] resolves, so a transient
/// loading frame can be asserted deterministically instead of racing a
/// real (near-instant) storage read.
class _GatedExportService implements LocalDataExportService {
  final ExportResult result;
  final Completer<void> gate = Completer<void>();

  _GatedExportService(this.result);

  @override
  Future<ExportResult> export() async {
    await gate.future;
    return result;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  LocalDataExportService? exportService,
}) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    MaterialApp(home: PrivacyScreen(exportService: exportService)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });
  tearDown(() {
    LocalNamespaceResolver.debugUidOverride = testNamespaceUid;
  });

  testWidgets(
    'explains local storage, cloud sync, AI usage, and notifications',
    (tester) async {
      await _pump(tester);

      expect(find.text('Local data'), findsOneWidget);
      expect(find.text('Cloud sync'), findsOneWidget);
      expect(find.text('AI features'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.textContaining('row-level'), findsNothing);
      expect(find.text('Export'), findsOneWidget);
    },
  );

  testWidgets('does not overclaim GDPR compliance', (tester) async {
    await _pump(tester);

    expect(find.textContaining('GDPR'), findsNothing);
  });

  testWidgets('has no delete account button', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Delete account'), findsNothing);
  });

  testWidgets('Export button shows a loading state then a JSON preview', (
    tester,
  ) async {
    final fake = _GatedExportService(
      ExportResult.success(
        LocalDataExport(
          generatedAt: DateTime.utc(2026, 1, 1),
          activeUid: testNamespaceUid,
          habitsRaw: const [
            {'id': 'h1'},
          ],
          adaptiveSuggestionsRaw: const [],
          appSettings: const {},
          syncMetadata: const {},
        ),
        '{"habits":[{"id":"h1"}]}',
      ),
    );
    await _pump(tester, exportService: fake);

    await tester.tap(find.byKey(exportDataButtonKey));
    await tester.pump();
    expect(find.text('Exporting…'), findsOneWidget);

    fake.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(exportJsonPreviewKey), findsOneWidget);
    final preview = tester.widget<SelectableText>(
      find.byKey(exportJsonPreviewKey),
    );
    expect(preview.data, contains('"h1"'));
  });

  testWidgets('Copy button copies the export JSON to the clipboard', (
    tester,
  ) async {
    final copyCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copyCalls.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final habitStorage = HabitStorage();
    await habitStorage.saveHabits([]);
    await _pump(
      tester,
      exportService: LocalDataExportService(habitStorage: habitStorage),
    );

    await tester.tap(find.byKey(exportDataButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(exportCopyButtonKey));
    await tester.pumpAndSettle();

    expect(copyCalls, hasLength(1));
    expect(copyCalls.single, contains('"habits"'));
    expect(find.byKey(exportCopiedMessageKey), findsOneWidget);
  });

  testWidgets('shows a friendly error, never a raw exception, on failure', (
    tester,
  ) async {
    LocalNamespaceResolver.debugUidOverride = null;
    await _pump(tester, exportService: LocalDataExportService());

    await tester.tap(find.byKey(exportDataButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(exportErrorMessageKey), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
  });
}
