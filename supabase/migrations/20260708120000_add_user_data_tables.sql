create table public.habits (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz null,
  payload jsonb not null,
  constraint habits_pkey primary key (user_id, id),
  constraint habits_id_not_blank check (length(btrim(id)) > 0),
  constraint habits_payload_object check (jsonb_typeof(payload) = 'object'),
  constraint habits_payload_id_matches check ((payload ->> 'id') is null or payload ->> 'id' = id),
  constraint habits_payload_title_not_blank check (
    (payload ->> 'title') is null or length(btrim(payload ->> 'title')) > 0
  )
);

comment on table public.habits is
  'Per-user habit records for future sync. Ownership is enforced by composite primary key and RLS; deleted_at stores tombstones.';
comment on column public.habits.payload is
  'Full Habit JSON payload. Ownership, id, timestamps, and tombstone remain first-class columns for RLS and sync queries.';

create table public.adaptive_suggestions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  habit_id text null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz null,
  payload jsonb not null,
  constraint adaptive_suggestions_pkey primary key (user_id, id),
  constraint adaptive_suggestions_id_not_blank check (length(btrim(id)) > 0),
  constraint adaptive_suggestions_habit_id_not_blank check (
    habit_id is null or length(btrim(habit_id)) > 0
  ),
  constraint adaptive_suggestions_payload_object check (jsonb_typeof(payload) = 'object'),
  constraint adaptive_suggestions_payload_id_matches check (
    (payload ->> 'id') is null or payload ->> 'id' = id
  ),
  constraint adaptive_suggestions_payload_habit_id_matches check (
    (payload ->> 'habitId') is null or payload ->> 'habitId' = habit_id
  )
);

comment on table public.adaptive_suggestions is
  'Per-user Adaptive Habit Coach suggestion records for future sync. No habit foreign key is used so habit tombstones and deleted habits remain compatible.';
comment on column public.adaptive_suggestions.payload is
  'Full AdaptiveHabitSuggestion JSON payload. Ownership, id, habit_id, timestamps, and tombstone remain first-class columns.';

create table public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  updated_at timestamptz not null,
  payload jsonb not null,
  constraint user_preferences_payload_object check (jsonb_typeof(payload) = 'object')
);

comment on table public.user_preferences is
  'One preferences row per user for future sync. SyncMetadata and RecoverySnapshot remain local-only.';
comment on column public.user_preferences.payload is
  'AppSettings JSON payload. updated_at remains first-class for sync queries.';

alter table public.habits enable row level security;
alter table public.adaptive_suggestions enable row level security;
alter table public.user_preferences enable row level security;

create policy habits_select_own on public.habits for select to authenticated using (auth.uid() = user_id);
create policy habits_insert_own on public.habits for insert to authenticated with check (auth.uid() = user_id);
create policy habits_update_own on public.habits for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy habits_delete_own on public.habits for delete to authenticated using (auth.uid() = user_id);

create policy adaptive_suggestions_select_own on public.adaptive_suggestions for select to authenticated using (auth.uid() = user_id);
create policy adaptive_suggestions_insert_own on public.adaptive_suggestions for insert to authenticated with check (auth.uid() = user_id);
create policy adaptive_suggestions_update_own on public.adaptive_suggestions for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy adaptive_suggestions_delete_own on public.adaptive_suggestions for delete to authenticated using (auth.uid() = user_id);

create policy user_preferences_select_own on public.user_preferences for select to authenticated using (auth.uid() = user_id);
create policy user_preferences_insert_own on public.user_preferences for insert to authenticated with check (auth.uid() = user_id);
create policy user_preferences_update_own on public.user_preferences for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy user_preferences_delete_own on public.user_preferences for delete to authenticated using (auth.uid() = user_id);

revoke all on table public.habits from anon;
revoke all on table public.adaptive_suggestions from anon;
revoke all on table public.user_preferences from anon;

grant select, insert, update, delete on table public.habits to authenticated;
grant select, insert, update, delete on table public.adaptive_suggestions to authenticated;
grant select, insert, update, delete on table public.user_preferences to authenticated;