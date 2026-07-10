-- ============================================================================
-- Last weights and all-time personal records
-- ============================================================================
-- Both tables are small, one-row-per-(user, exercise) caches used to prefill
-- the workout screen with "what did I lift last time" and to detect new PRs
-- without scanning the full workout_logs history on every finished set.
--
-- last_weights.sets is JSONB (not a child table like workout_log_sets):
-- it's a snapshot of the most recent session only, always read and written
-- as a whole, never filtered or aggregated — the opposite access pattern
-- from workout_log_sets, so JSONB is the right call here.
-- ============================================================================

create table public.last_weights (
  user_id      uuid not null references auth.users (id) on delete cascade,
  exercise_id  text not null references public.exercises (id) on delete cascade,
  weight       real not null default 0,
  reps         smallint not null default 0,
  sets         jsonb not null default '[]'::jsonb,
  history      text not null default '' check (char_length(history) <= 200),
  updated_at   timestamptz not null default now(),
  primary key (user_id, exercise_id)
);

comment on column public.last_weights.history is 'Precomputed display string (e.g. "40kg · 8/8/8"), matching the client app''s existing format.';

create trigger last_weights_set_updated_at
  before update on public.last_weights
  for each row
  execute function public.set_updated_at();

create table public.all_time_prs (
  user_id      uuid not null references auth.users (id) on delete cascade,
  exercise_id  text not null references public.exercises (id) on delete cascade,
  weight       real not null,
  achieved_at  timestamptz not null default now(),
  primary key (user_id, exercise_id)
);

comment on table public.all_time_prs is 'Heaviest weight ever logged per (user, exercise). One row per pair — updated in place, not appended to.';

-- ── Row Level Security ──
alter table public.last_weights enable row level security;
alter table public.all_time_prs enable row level security;

create policy "Users can manage their own last weights"
  on public.last_weights for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can manage their own personal records"
  on public.all_time_prs for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
