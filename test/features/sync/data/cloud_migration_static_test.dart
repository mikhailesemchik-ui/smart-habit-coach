import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Phase 3 migration defines owned tables, cascades, composite keys, and RLS policies',
    () {
      final sql = File(
        'supabase/migrations/20260708120000_add_user_data_tables.sql',
      ).readAsStringSync();

      for (final table in [
        'habits',
        'adaptive_suggestions',
        'user_preferences',
      ]) {
        expect(sql, contains('create table public.$table'));
        expect(
          sql,
          contains('alter table public.$table enable row level security'),
        );
        expect(sql, contains('references auth.users(id) on delete cascade'));
        expect(sql, contains('${table}_select_own'));
        expect(sql, contains('${table}_insert_own'));
        expect(sql, contains('${table}_update_own'));
        expect(sql, contains('${table}_delete_own'));
        expect(sql, contains('auth.uid() = user_id'));
      }

      expect(sql, contains('constraint habits_pkey primary key (user_id, id)'));
      expect(
        sql,
        contains(
          'constraint adaptive_suggestions_pkey primary key (user_id, id)',
        ),
      );
      expect(
        sql,
        contains(
          'user_id uuid primary key references auth.users(id) on delete cascade',
        ),
      );
      expect(sql, isNot(contains('service_role')));
      expect(sql, isNot(contains('using (true)')));
      expect(sql, isNot(contains('with check (true)')));
    },
  );
}
