-- ============================================================================
-- Weight-logging preferences + 3 new dumbbell exercises + 3 renames
-- ============================================================================
-- Part of the "true weight" feature: the client now normalizes the raw
-- number typed into a weight field (barbell per-side vs total, dumbbell
-- per-hand vs total, bodyweight-inclusive for weighted pull-ups) before
-- using it in 1RM math or history/volume displays — see getTrueWeight()
-- in index.html. That normalization is driven entirely by client-side
-- constants (DEFAULT_EXERCISES' new `equipment`/`unilateral`/etc fields)
-- and one small per-user preference object, so this migration only needs
-- two things:
--
--   1. A `weight_prefs` jsonb column on user_settings — same "small,
--      whole-row, never filtered" reasoning as schedule/last_notes on
--      this table (see 20260710000005_user_settings.sql).
--   2. public.exercises catches up with 3 client-side renames (adding a
--      "Barbell"/"(Unilateral)" qualifier to disambiguate from 3 new
--      dumbbell exercises added alongside them) and those 3 new rows —
--      same "routine_exercises/user_exercise_notes/last_weights/
--      all_time_prs all have a hard foreign key into this table" reason
--      as the previous catalogue syncs. `equipment`/`unilateral`/etc are
--      NOT added here — they're pure client-side display/calculation
--      constants the server never reads or writes, so there's nothing
--      for this table to gain by duplicating them.
-- ============================================================================

alter table public.user_settings add column weight_prefs jsonb not null default '{"barbellMode":"total","barWeightKg":20,"dumbbellMode":"perDumbbell","bodyweightKg":null}'::jsonb;

comment on column public.user_settings.weight_prefs is 'How to interpret the raw number typed into a weight field (barbell total/per-side + bar weight, dumbbell per-hand/total) plus optional bodyweight, used for 1RM math and true-weight displays. See getTrueWeight() in index.html.';

-- ── Renames: disambiguating from the 3 new dumbbell variants below ──
update public.exercises set name = 'Barbell Romanian Deadlift' where id = 'e02';
update public.exercises set name = 'Barbell Deadlift' where id = 'e36';
update public.exercises set name = 'Barbell Standing Military Press' where id = 'e75';

-- ── Unilateral retags: these are physically always one-arm-at-a-time,
--    matching the "(Unilateral)" convention this catalogue already uses
--    elsewhere — was previously missing on these 3. ──
update public.exercises set name = 'Dumbbell Concentration Curl (Unilateral)' where id = 'e47';
update public.exercises set name = 'Dumbbell Triceps Kickback (Unilateral)' where id = 'e49';
update public.exercises set name = 'Dumbbell Preacher Curl (Unilateral)' where id = 'e80';

-- ── New: dumbbell counterparts of the 3 renamed barbell lifts above ──
insert into public.exercises (id, name, muscle_group, tracking_type) values
  ('e112', 'Dumbbell Romanian Deadlift', 'Legs', 'reps'),
  ('e113', 'Dumbbell Deadlift', 'Legs', 'reps'),
  ('e114', 'Dumbbell Standing Military Press', 'Shoulders', 'reps');

-- ── Row-count assertion ──
-- 109 after the last catalogue sync + 3 new = 112.
do $$
declare
  cnt integer;
begin
  select count(*) into cnt from public.exercises;
  if cnt <> 112 then
    raise exception 'Expected 112 exercises after sync, found %', cnt;
  end if;
end $$;
