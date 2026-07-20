-- ============================================================================
-- Sync public.exercises with the client's DEFAULT_EXERCISES catalogue
-- ============================================================================
-- public.exercises was seeded once (20260710000002) with the original 75
-- exercises and had not been touched since. Meanwhile the client-side
-- catalogue in index.html grew during this session's video-matching review
-- and a full naming-consistency pass (singular exercise names, consistent
-- equipment prefixes), then gained a new Cardio muscle group. This
-- migration brings the table up to the client's final state:
--
--   1. Adds a `tracking_type` column ('reps' | 'time') so the catalogue
--      records which exercises are timed holds/cardio rather than that
--      living only in the client's DEFAULT_EXERCISES array.
--   2. Widens the muscle_group check constraint to allow 'Cardio'.
--   3. Inserts the 34 exercises added this session (27 from the video-match
--      review, 7 new Cardio machines) — this is not cosmetic: routine_exercises,
--      user_exercise_notes, last_weights and all_time_prs all have a hard
--      foreign key into this table, so any user syncing a routine/note/set
--      that references one of these ids currently hits a foreign key
--      violation, because the ids don't exist server-side yet.
--   4. Updates the name (and, for 3 pre-existing holds, tracking_type) of
--      every exercise renamed on the client this session.
-- ============================================================================

alter table public.exercises
  add column tracking_type text not null default 'reps' check (tracking_type in ('reps', 'time'));

comment on column public.exercises.tracking_type is '''reps'': tracked by sets/reps/weight (default). ''time'': tracked by duration — isometric holds and Cardio machines.';

alter table public.exercises drop constraint exercises_muscle_group_check;
alter table public.exercises add constraint exercises_muscle_group_check
  check (muscle_group in ('Legs', 'Chest', 'Back', 'Shoulders', 'Triceps', 'Biceps', 'Core', 'Cardio'));

-- ── 1. New exercises added this session (e78-e104 from the video-match
--       review, e105-e111 the new Cardio group) ──
insert into public.exercises (id, name, muscle_group, tracking_type) values
  ('e78', 'Barbell Hack Squat', 'Legs', 'reps'),
  ('e79', 'Barbell Shrug', 'Back', 'reps'),
  ('e80', 'Dumbbell Preacher Curl', 'Biceps', 'reps'),
  ('e81', 'Split Squat', 'Legs', 'reps'),
  ('e82', 'Resistance Band Hip Thrust on Knees', 'Legs', 'reps'),
  ('e83', 'Dumbbell Lunge', 'Legs', 'reps'),
  ('e84', 'Cable Upper Chest Crossover', 'Chest', 'reps'),
  ('e85', 'Cable Low Seated Row', 'Back', 'reps'),
  ('e86', 'Dumbbell Bent Over Row', 'Back', 'reps'),
  ('e87', 'Smith Standing Military Press', 'Shoulders', 'reps'),
  ('e88', 'Front Plank with Twist', 'Core', 'time'),
  ('e89', 'Seated Leg Raise', 'Core', 'reps'),
  ('e90', 'Bodyweight Incline Side Plank', 'Core', 'time'),
  ('e91', 'Dumbbell Goblet Squat', 'Legs', 'reps'),
  ('e92', 'Barbell Front Squat', 'Legs', 'reps'),
  ('e93', 'Barbell Sumo Deadlift', 'Legs', 'reps'),
  ('e94', 'Barbell Good Morning', 'Legs', 'reps'),
  ('e95', 'Barbell Glute Bridge', 'Legs', 'reps'),
  ('e96', 'Dumbbell Step-Up', 'Legs', 'reps'),
  ('e97', 'Barbell Rack Pull', 'Legs', 'reps'),
  ('e98', 'Weighted Svend Press', 'Chest', 'reps'),
  ('e99', 'Cable Straight Arm Pulldown', 'Back', 'reps'),
  ('e100', 'Dumbbell Arnold Press', 'Shoulders', 'reps'),
  ('e101', 'EZ Barbell Spider Curl', 'Biceps', 'reps'),
  ('e102', 'Dumbbell Zottman Curl', 'Biceps', 'reps'),
  ('e103', 'Dead Bug', 'Core', 'reps'),
  ('e104', 'Mountain Climber', 'Core', 'reps'),
  ('e105', 'Running (Treadmill)', 'Cardio', 'time'),
  ('e106', 'Cycling (Stationary Bike)', 'Cardio', 'time'),
  ('e107', 'Stair Climber', 'Cardio', 'time'),
  ('e108', 'Elliptical', 'Cardio', 'time'),
  ('e109', 'Rowing Machine', 'Cardio', 'time'),
  ('e110', 'Jump Rope', 'Cardio', 'time'),
  ('e111', 'Incline Walk (Treadmill)', 'Cardio', 'time');

-- ── 2. Renames applied on the client this session, not yet mirrored here ──
update public.exercises set name = 'Barbell Squat' where id = 'e01';
update public.exercises set name = 'Bulgarian Split Squat' where id = 'e61';
update public.exercises set name = 'Hack Squat' where id = 'e62';
update public.exercises set name = 'Romanian Deadlift' where id = 'e02';
update public.exercises set name = 'Deadlift' where id = 'e36';
update public.exercises set name = 'Hip Thrust' where id = 'e03';
update public.exercises set name = 'Leg Extension' where id = 'e04';
update public.exercises set name = 'Lying Leg Curl' where id = 'e35';
update public.exercises set name = 'Sitting Leg Curl' where id = 'e77';
update public.exercises set name = 'Leg Curl (Unilateral)' where id = 'e07';
update public.exercises set name = 'Seated Hip Adduction' where id = 'e08';
update public.exercises set name = 'Seated Hip Abduction (Glutes)' where id = 'e32';
update public.exercises set name = 'Cable Glute Kickback' where id = 'e09';
update public.exercises set name = 'Walking Lunge' where id = 'e63';
update public.exercises set name = 'Lunge' where id = 'e64';
update public.exercises set name = 'Calf Raise' where id = 'e37';
update public.exercises set name = 'Dumbbell Calf Raise (Unilateral)' where id = 'e38';
update public.exercises set name = 'Haka Calf Raise' where id = 'e05';
update public.exercises set name = 'Haka Calf Raise (Unilateral)' where id = 'e39';
update public.exercises set name = 'Barbell Bench Press' where id = 'e10';
update public.exercises set name = 'Barbell Incline Bench Press' where id = 'e11';
update public.exercises set name = 'Dumbbell Incline Bench Press' where id = 'e41';
update public.exercises set name = 'Barbell Decline Bench Press' where id = 'e65';
update public.exercises set name = 'Machine Chest Fly' where id = 'e13';
update public.exercises set name = 'Cable Seated Chest Press' where id = 'e14';
update public.exercises set name = 'Cable Chest Crossover' where id = 'e66';
update public.exercises set name = 'Push-Up' where id = 'e42';
update public.exercises set name = 'Pull-Up' where id = 'e24';
update public.exercises set name = 'Cable Pulldown' where id = 'e20';
update public.exercises set name = 'Barbell Bent Over Row' where id = 'e23';
update public.exercises set name = 'Chest Supported Row' where id = 'e21';
update public.exercises set name = 'Chest Supported Row (Unilateral)' where id = 'e25';
update public.exercises set name = 'Cable Seated Row' where id = 'e67';
update public.exercises set name = 'Low Cable Row (Unilateral)' where id = 'e26';
update public.exercises set name = 'Dumbbell Bent Over Row (Unilateral)' where id = 'e43';
update public.exercises set name = 'T-Bar Row' where id = 'e68';
update public.exercises set name = 'Dumbbell Shrug' where id = 'e31';
update public.exercises set name = 'Hyperextension' where id = 'e69';
update public.exercises set name = 'Standing Military Press' where id = 'e75';
update public.exercises set name = 'Dumbbell Lateral Raise' where id = 'e12';
update public.exercises set name = 'Dumbbell Front Raise' where id = 'e71';
update public.exercises set name = 'Barbell Upright Row' where id = 'e72';
update public.exercises set name = 'Dumbbell Reverse Fly' where id = 'e70';
update public.exercises set name = 'Cable Face Pull' where id = 'e15';
update public.exercises set name = 'Cable Overhead Triceps Extension' where id = 'e18';
update public.exercises set name = 'Cable Overhead Triceps Extension (Unilateral)' where id = 'e34';
update public.exercises set name = 'Cable Triceps Pushdown (V-Bar)' where id = 'e17';
update public.exercises set name = 'Cable Triceps Pushdown (Unilateral)' where id = 'e33';
update public.exercises set name = 'Triceps Dip' where id = 'e19';
update public.exercises set name = 'Skull Crusher' where id = 'e48';
update public.exercises set name = 'Dumbbell Triceps Kickback' where id = 'e49';
update public.exercises set name = 'Diamond Push-Up' where id = 'e50';
update public.exercises set name = 'Dumbbell Biceps Curl' where id = 'e29';
update public.exercises set name = 'Barbell Biceps Curl' where id = 'e73';
update public.exercises set name = 'Cable Biceps Curl' where id = 'e30';
update public.exercises set name = 'Dumbbell Hammer Curl' where id = 'e45';
update public.exercises set name = 'Dumbbell Incline Curl' where id = 'e46';
update public.exercises set name = 'EZ-Bar Preacher Curl' where id = 'e27';
update public.exercises set name = 'Declined Dumbbell Curl' where id = 'e28';
update public.exercises set name = 'Dumbbell Concentration Curl' where id = 'e47';
update public.exercises set name = 'Crunch' where id = 'e52';
update public.exercises set name = 'Russian Twist' where id = 'e56';
update public.exercises set name = 'Leg Raise' where id = 'e53';
update public.exercises set name = 'Hanging Leg Raise' where id = 'e57';
update public.exercises set name = 'Cable Crunch' where id = 'e54';
update public.exercises set name = 'Wheel Rollout' where id = 'e55';

-- ── 3. Pre-existing isometric holds — name unchanged, now flagged as time-tracked ──
update public.exercises set tracking_type = 'time' where id in ('e51', 'e58', 'e74');

-- ── Row-count assertion ──
-- Guards against a partial apply (e.g. connection drop mid-migration)
-- silently leaving the catalogue half-synced. 75 original + 34 new = 109.
do $$
declare
  cnt integer;
begin
  select count(*) into cnt from public.exercises;
  if cnt <> 109 then
    raise exception 'Expected 109 exercises after sync, found %', cnt;
  end if;
end $$;
