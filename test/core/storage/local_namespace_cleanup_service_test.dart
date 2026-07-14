import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_habit_coach/core/storage/local_namespace_cleanup_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('removes every namespaced key for the given uid', () async {
    SharedPreferences.setMockInitialValues({
      'habits:uid-a': '[]',
      'adaptive_suggestions:uid-a': '[]',
      'app_settings:uid-a': '{}',
      'sync_metadata:uid-a': '{}',
      'recovery_snapshot:uid-a': '{}',
      'local_schema_version:uid-a': 1,
    });

    await const LocalNamespaceCleanupService().wipeNamespace('uid-a');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('habits:uid-a'), isNull);
    expect(prefs.getString('adaptive_suggestions:uid-a'), isNull);
    expect(prefs.getString('app_settings:uid-a'), isNull);
    expect(prefs.getString('sync_metadata:uid-a'), isNull);
    expect(prefs.getString('recovery_snapshot:uid-a'), isNull);
    expect(prefs.getInt('local_schema_version:uid-a'), isNull);
  });

  test('does not remove another uid\'s data', () async {
    SharedPreferences.setMockInitialValues({
      'habits:uid-a': '[]',
      'habits:uid-b': '["kept"]',
    });

    await const LocalNamespaceCleanupService().wipeNamespace('uid-a');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('habits:uid-a'), isNull);
    expect(prefs.getString('habits:uid-b'), '["kept"]');
  });

  test('is safe to call when no keys exist for the uid', () async {
    await const LocalNamespaceCleanupService().wipeNamespace('never-existed');
  });
}
