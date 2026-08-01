-- ============================================================================
-- PR events — feeds a new "so-and-so just hit a PR" row into the
-- Interactions bell, alongside the existing follow/ping events.
-- ============================================================================
-- One row per all-time personal record that genuinely raised a lift's
-- estimated 1RM. NOT every logged set, NOT every workout, and explicitly
-- NOT the duration-based "PR" recorded for time-tracked exercises (planks,
-- cardio holds) — Alan's own words: "siempre que se le calcule en base al
-- 1RM, osea que sea un PR que aumenta su 1RM." The client only inserts a row
-- from the exact branch of finishWorkout() that already decides a stored
-- allTimePRs record improved (the same check that updates the PR ledger
-- shown on the person's own profile), so this table can never disagree with
-- what the PR tab itself shows.
--
-- weight/reps are stored RAW (as typed), same convention as workout_log_sets
-- /last_weights/all_time_prs — normalization into a real display number
-- (per-side barbell, per-dumbbell, bodyweight-assisted, kg/lb) happens on
-- READ via the viewer's own getTrueWeight()/fmtPRWeight(), exactly how the
-- PRs tab already renders someone else's history. Storing a pre-normalized
-- number here would fix it to whichever weight-logging convention happened
-- to be selected on the PR-holder's device at that moment, which is wrong
-- for every other viewer.
--
-- INSERT-only, no UPDATE/DELETE policy — an immutable notification log,
-- same shape as public.pings.
-- ============================================================================

create table public.pr_events (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  exercise_id  text not null references public.exercises (id) on delete cascade,
  weight       real not null,
  reps         smallint not null,
  created_at   timestamptz not null default now(),

  check (weight > 0),
  check (reps > 0)
);

comment on table public.pr_events is 'Immutable log of all-time-1RM-raising PRs, one row per improvement. Feeds followers'' Interactions notifications. Time-tracked (duration) PRs are deliberately never written here.';

-- Covers "PR events belonging to people I follow", the Interactions feed's
-- query shape: an IN-list of followed user ids, most recent first.
create index pr_events_user_id_created_at_idx on public.pr_events (user_id, created_at desc);

alter table public.pr_events enable row level security;

-- INSERT: only ever as yourself.
create policy "Users can log their own PR events"
  on public.pr_events for insert
  with check (auth.uid() = user_id);

-- SELECT: exactly the same rule already governing whether you can see this
-- person's workout log / routines / schedule (public.can_view_profile_content,
-- defined in 20260715000003 and widened in 20260726000003) — own data, a
-- public profile, an accepted follow, or an active trainer connection.
-- Reusing it rather than inventing a parallel visibility rule keeps this in
-- lockstep with whatever "can view this person's training" already means
-- elsewhere in the app.
create policy "Visible to whoever can already view this user's training"
  on public.pr_events for select
  using (auth.uid() = user_id or public.can_view_profile_content(user_id));
