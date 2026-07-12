-- ============================================================================
-- Routines
-- ============================================================================
-- Unlike the exercise catalogue, routines ARE per-user: each person builds
-- their own workout day plans (which exercises, in what order, with what
-- target sets/reps/weight/rest). `routines` holds the routine itself,
-- `routine_exercises` holds its ordered exercise list.
--
-- `client_id` carries the local app's own routine id (e.g. "r01") so the
-- sync layer can UPSERT by (user_id, client_id) instead of deleting and
-- reinserting on every sync. Reinserting would mint a new `id` each time,
-- which would silently null out `workout_logs.routine_id` on every past
-- session performed under that routine (its on-delete-set-null foreign
-- key firing on the "deleted" old row) — client_id keeps the real `id`
-- stable across repeated syncs so history stays linked.
-- ============================================================================

create table public.routines (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  client_id   text not null check (char_length(client_id) <= 50),
  name        text not null check (char_length(name) <= 100),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  unique (user_id, client_id)
);

comment on column public.routines.client_id is 'Stable id assigned by the client app; sync upserts on (user_id, client_id) to avoid minting a new row (and breaking history links) on every sync.';

create index routines_user_id_idx on public.routines (user_id);

create trigger routines_set_updated_at
  before update on public.routines
  for each row
  execute function public.set_updated_at();

create table public.routine_exercises (
  id            uuid primary key default gen_random_uuid(),
  routine_id    uuid not null references public.routines (id) on delete cascade,
  exercise_id   text not null references public.exercises (id),
  position      smallint not null,
  target_sets   smallint not null default 3,
  target_reps   smallint not null default 8,
  target_weight real not null default 0,
  rest_seconds  smallint not null default 90,

  -- Enforces a single, unambiguous exercise ordering per routine, and makes
  -- "give me this routine's exercises in order" a plain indexed sort instead
  -- of relying on client-side array order that could get corrupted.
  unique (routine_id, position)
);

comment on column public.routine_exercises.target_weight is 'Planned starting weight in kg; the actual weight lifted each session is recorded in workout_log_sets, not here.';

-- routine_id is covered by the unique index above, but exercise_id lookups
-- ("which routines use exercise X") still need their own index.
create index routine_exercises_exercise_id_idx on public.routine_exercises (exercise_id);

-- ── Row Level Security ──
-- Ownership of a routine_exercises row is determined by its parent routine's
-- user_id, since routine_exercises has no user_id column of its own.
alter table public.routines enable row level security;
alter table public.routine_exercises enable row level security;

create policy "Users can manage their own routines"
  on public.routines for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can manage exercises within their own routines"
  on public.routine_exercises for all
  using (
    exists (
      select 1 from public.routines
      where routines.id = routine_exercises.routine_id
        and routines.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.routines
      where routines.id = routine_exercises.routine_id
        and routines.user_id = auth.uid()
    )
  );
