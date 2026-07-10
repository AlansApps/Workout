-- ============================================================================
-- Exercise catalogue (shared, global)
-- ============================================================================
-- The exercise list (name + muscle group) is the same for every user today —
-- there is no "add custom exercise" feature in the app. Storing it once here
-- instead of copying it into every user's data keeps storage flat as the
-- user base grows: this table has ~75 rows total, forever, regardless of
-- how many people use the app.
--
-- Personal, per-user notes about an exercise (e.g. "seat position 5 on my
-- gym's machine") live separately in user_exercise_notes (next migration),
-- since those genuinely differ per person.
--
-- `id` reuses the short codes already used in the client app's local
-- storage (e01, e02, ...) so the eventual local-to-cloud data migration can
-- match rows by id directly instead of remapping identifiers.
-- ============================================================================

create table public.exercises (
  id            text primary key,
  name          text not null check (char_length(name) <= 100),
  muscle_group  text not null check (
    muscle_group in ('Legs', 'Chest', 'Back', 'Shoulders', 'Triceps', 'Biceps', 'Core')
  ),
  created_at    timestamptz not null default now()
);

comment on table public.exercises is 'Shared, global exercise catalogue. Not owned by any single user.';

-- No index on muscle_group: this table has ~75 rows and only 7 distinct
-- values, so Postgres will sequential-scan it regardless — an index here
-- would only add write/storage overhead with no read benefit.

-- ── Row Level Security ──
-- Every authenticated user can read the catalogue. Nobody can write to it
-- through the API — it's maintained only via migrations (or, later, an
-- admin-only path) until a "custom exercise" feature is designed.
alter table public.exercises enable row level security;

create policy "Authenticated users can read the exercise catalogue"
  on public.exercises for select
  to authenticated
  using (true);

-- ── Seed data ──
-- Mirrors DEFAULT_EXERCISES from the client app (name + muscle group only;
-- notes are intentionally excluded, see comment above).
insert into public.exercises (id, name, muscle_group) values
  ('e01', 'Squats', 'Legs'),
  ('e61', 'Bulgarian Split Squats', 'Legs'),
  ('e62', 'Hack Squats', 'Legs'),
  ('e06', 'Leg Press', 'Legs'),
  ('e02', 'Romanian Deadlifts', 'Legs'),
  ('e36', 'Deadlifts', 'Legs'),
  ('e03', 'Hip Thrusts', 'Legs'),
  ('e04', 'Leg Extensions', 'Legs'),
  ('e35', 'Lying Leg Curls', 'Legs'),
  ('e77', 'Sitting Leg Curls', 'Legs'),
  ('e07', 'Leg Curls (Unilateral)', 'Legs'),
  ('e08', 'Adductors', 'Legs'),
  ('e32', 'Abductors (Glutes)', 'Legs'),
  ('e09', 'Glute Kickbacks', 'Legs'),
  ('e63', 'Walking Lunges', 'Legs'),
  ('e64', 'Lunges', 'Legs'),
  ('e37', 'Calf Raises', 'Legs'),
  ('e38', 'Calf Raises (Unilateral)', 'Legs'),
  ('e05', 'Haka Calf Raises', 'Legs'),
  ('e39', 'Haka Calf Raises (Unilateral)', 'Legs'),
  ('e10', 'Bench Press', 'Chest'),
  ('e40', 'Dumbbell Bench Press', 'Chest'),
  ('e11', 'Incline Bench', 'Chest'),
  ('e41', 'Dumbbell Incline Press', 'Chest'),
  ('e65', 'Decline Bench Press', 'Chest'),
  ('e13', 'Chest Fly Machine', 'Chest'),
  ('e60', 'Dumbbell Chest Fly', 'Chest'),
  ('e14', 'Cable Chest', 'Chest'),
  ('e66', 'Cable Crossover', 'Chest'),
  ('e42', 'Push-Ups', 'Chest'),
  ('e24', 'Pull-Ups', 'Back'),
  ('e20', 'Pulldowns', 'Back'),
  ('e23', 'Barbell Rows', 'Back'),
  ('e21', 'Chest Supported Rows', 'Back'),
  ('e25', 'Chest Supported Rows (Unilateral)', 'Back'),
  ('e67', 'Seated Cable Rows', 'Back'),
  ('e26', 'Low Cable Rows (Unilateral)', 'Back'),
  ('e43', 'Dumbbell Row (Unilateral)', 'Back'),
  ('e68', 'T-Bar Rows', 'Back'),
  ('e22', 'One-Arm Cable Pullover', 'Back'),
  ('e31', 'Shrugs', 'Back'),
  ('e69', 'Hyperextensions', 'Back'),
  ('e16', 'Dumbbell Shoulder Press', 'Shoulders'),
  ('e75', 'Military Shoulder Press', 'Shoulders'),
  ('e76', 'Machine Shoulder Press', 'Shoulders'),
  ('e12', 'Lateral Raises', 'Shoulders'),
  ('e71', 'Front Raises', 'Shoulders'),
  ('e72', 'Upright Rows', 'Shoulders'),
  ('e70', 'Rear Delt Fly', 'Shoulders'),
  ('e15', 'Face Pulls', 'Shoulders'),
  ('e18', 'Overhead Cable Extensions', 'Triceps'),
  ('e34', 'Overhead Cable Extensions (Unilateral)', 'Triceps'),
  ('e17', 'Pushdown W', 'Triceps'),
  ('e33', 'Cable Pushdowns (Unilateral)', 'Triceps'),
  ('e19', 'Dips', 'Triceps'),
  ('e48', 'Skull Crushers', 'Triceps'),
  ('e49', 'Tricep Kickbacks', 'Triceps'),
  ('e50', 'Diamond Push-Ups', 'Triceps'),
  ('e29', 'Dumbbell Curls', 'Biceps'),
  ('e73', 'Barbell Curls', 'Biceps'),
  ('e30', 'Cable Curls', 'Biceps'),
  ('e45', 'Hammer Curls', 'Biceps'),
  ('e46', 'Incline Dumbbell Curls', 'Biceps'),
  ('e27', 'Preacher Curls', 'Biceps'),
  ('e28', 'Declined Dumbbell Curls', 'Biceps'),
  ('e47', 'Concentration Curls', 'Biceps'),
  ('e51', 'Plank', 'Core'),
  ('e52', 'Crunches', 'Core'),
  ('e56', 'Russian Twists', 'Core'),
  ('e53', 'Leg Raises', 'Core'),
  ('e57', 'Hanging Leg Raises', 'Core'),
  ('e54', 'Cable Crunches', 'Core'),
  ('e55', 'Ab Wheel', 'Core'),
  ('e58', 'Superman Plank', 'Core'),
  ('e74', 'Side Plank', 'Core');
