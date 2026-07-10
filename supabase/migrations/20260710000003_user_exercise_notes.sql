-- ============================================================================
-- Per-user exercise notes
-- ============================================================================
-- Personal notes about an exercise (gym machine settings, form cues, etc.)
-- differ per user even though the exercise itself is shared. This table is
-- intentionally sparse: most (user, exercise) pairs will never get a row,
-- since most users won't annotate most exercises.
-- ============================================================================

create table public.user_exercise_notes (
  user_id      uuid not null references auth.users (id) on delete cascade,
  exercise_id  text not null references public.exercises (id) on delete cascade,
  notes        text not null default '' check (char_length(notes) <= 2000),
  updated_at   timestamptz not null default now(),
  primary key (user_id, exercise_id)
);

comment on table public.user_exercise_notes is 'Sparse table: only exercises a user has actually annotated get a row.';

create trigger user_exercise_notes_set_updated_at
  before update on public.user_exercise_notes
  for each row
  execute function public.set_updated_at();

-- ── Row Level Security ──
alter table public.user_exercise_notes enable row level security;

create policy "Users can manage their own exercise notes"
  on public.user_exercise_notes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
