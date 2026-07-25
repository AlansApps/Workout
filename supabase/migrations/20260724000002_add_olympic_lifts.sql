-- ============================================================================
-- Add the 3 Olympic lifts to the catalogue
-- ============================================================================
-- Revised PR-tracked-exercise list (2026-07-24, Alan's call after checking
-- which lifts people actually 1RM-test): Snatch, Clean and Jerk, and Power
-- Clean added as trackable lifts alongside the existing Squat/Deadlift/
-- Romanian Deadlift/Bench/Pull-Up/Military Press. Same reason as every
-- prior catalogue-sync migration — routine_exercises/user_exercise_notes/
-- last_weights/all_time_prs/workout_log_sets all have a hard foreign key
-- into this table, so a client syncing a routine/note/set referencing one
-- of these new ids hits a foreign key violation until the row exists here.
-- ============================================================================

insert into public.exercises (id, name, muscle_group, tracking_type) values
  ('e115', 'Barbell Snatch', 'Legs', 'reps'),
  ('e116', 'Barbell Clean and Jerk', 'Legs', 'reps'),
  ('e117', 'Barbell Power Clean', 'Legs', 'reps');

-- ── Row-count assertion ──
-- 112 after the previous sync + 3 new = 115.
do $$
declare
  cnt integer;
begin
  select count(*) into cnt from public.exercises;
  if cnt <> 115 then
    raise exception 'Expected 115 exercises after sync, found %', cnt;
  end if;
end $$;
