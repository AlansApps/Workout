-- ============================================================================
-- Workout history
-- ============================================================================
-- The append-only log of completed sessions. This is the table most likely
-- to grow large over time (one row per finished workout, forever), so it's
-- kept lean: fixed-size numeric columns, length-capped text, and no
-- redundant per-set duplication of exercise metadata beyond a name snapshot
-- (so history still reads correctly even if an exercise gets renamed or
-- removed from the catalogue later).
--
-- Three levels mirror the shape of a finished session exactly:
--   workout_logs           - one row per finished workout
--   workout_log_exercises  - one row per exercise performed in that workout
--   workout_log_sets       - one row per set of that exercise
-- The exercise name snapshot lives on workout_log_exercises (once per
-- exercise performed), not repeated on every one of its sets.
--
-- Sets are relational, not a JSONB array: per-set weight/reps is exactly the
-- kind of data future features (progress charts, volume trends, PR
-- detection) will want to filter and aggregate across rows.
-- ============================================================================

create table public.workout_logs (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  client_id         text check (char_length(client_id) <= 50),
  routine_id        uuid references public.routines (id) on delete set null,
  routine_name      text not null check (char_length(routine_name) <= 100),
  performed_at      timestamptz not null default now(),
  duration_seconds  smallint not null,
  note              text not null default '' check (char_length(note) <= 1000),

  unique (user_id, client_id)
);

comment on column public.workout_logs.client_id is 'The local app''s own log entry id (a base36 timestamp). Lets the sync layer tell "already uploaded this session" apart from "new session" without guessing from date/duration — nullable because it only exists for logs that originated on a client device.';
comment on column public.workout_logs.routine_id is 'Nullable: a routine can be deleted later without deleting its workout history.';
comment on column public.workout_logs.duration_seconds is 'smallint caps at ~9.1 hours, comfortably above any real workout session.';

-- Covers both "this user's history" and "this user's history in date order",
-- the two access patterns the app actually needs (log screen, progress screen).
create index workout_logs_user_id_performed_at_idx
  on public.workout_logs (user_id, performed_at desc);

create table public.workout_log_exercises (
  id             uuid primary key default gen_random_uuid(),
  log_id         uuid not null references public.workout_logs (id) on delete cascade,
  exercise_id    text references public.exercises (id) on delete set null,
  exercise_name  text not null check (char_length(exercise_name) <= 100),
  position       smallint not null,

  -- One row per exercise per workout, in a single well-defined order.
  unique (log_id, position)
);

comment on column public.workout_log_exercises.exercise_id is 'Nullable: preserves history even if the exercise catalogue entry is ever removed.';
comment on column public.workout_log_exercises.exercise_name is 'Snapshot of the exercise name at the time it was logged, so history reads correctly even after a catalogue rename. Stored once per exercise performed, not once per set.';

create index workout_log_exercises_exercise_id_idx on public.workout_log_exercises (exercise_id);

create table public.workout_log_sets (
  id                uuid primary key default gen_random_uuid(),
  log_exercise_id   uuid not null references public.workout_log_exercises (id) on delete cascade,
  set_index         smallint not null,
  weight            real not null,
  reps              smallint not null,

  unique (log_exercise_id, set_index)
);

-- ── Row Level Security ──
alter table public.workout_logs enable row level security;
alter table public.workout_log_exercises enable row level security;
alter table public.workout_log_sets enable row level security;

create policy "Users can manage their own workout logs"
  on public.workout_logs for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can manage exercises within their own workout logs"
  on public.workout_log_exercises for all
  using (
    exists (
      select 1 from public.workout_logs
      where workout_logs.id = workout_log_exercises.log_id
        and workout_logs.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.workout_logs
      where workout_logs.id = workout_log_exercises.log_id
        and workout_logs.user_id = auth.uid()
    )
  );

create policy "Users can manage sets within their own workout logs"
  on public.workout_log_sets for all
  using (
    exists (
      select 1 from public.workout_log_exercises
      join public.workout_logs on workout_logs.id = workout_log_exercises.log_id
      where workout_log_exercises.id = workout_log_sets.log_exercise_id
        and workout_logs.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.workout_log_exercises
      join public.workout_logs on workout_logs.id = workout_log_exercises.log_id
      where workout_log_exercises.id = workout_log_sets.log_exercise_id
        and workout_logs.user_id = auth.uid()
    )
  );
