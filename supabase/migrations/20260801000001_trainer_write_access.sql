-- ============================================================================
-- Trainer write access — the trainer tab stops being read-mostly
-- ============================================================================
-- Alan's spec: a trainer should be able to build a connected student's real
-- plan (not a disconnected snapshot copy), fill in weights, and log a
-- session on their behalf when running an in-person session — always
-- bounded by "create and modify, never delete" anything the student owns.
--
-- is_active_trainer_of() is the one gate every new policy below shares —
-- same non-expired, status='active' check can_view_profile_content()
-- already uses for READ access, pulled out on its own because these are
-- WRITE policies and "the trainer half of an active connection" needs to
-- be asked far more times here than the existing read-only helper does.
-- ============================================================================

create or replace function public.is_active_trainer_of(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.trainer_connections tc
    where tc.trainer_id = auth.uid()
      and tc.student_id = target_user_id
      and tc.status = 'active'
      and tc.expires_at > now()
  );
$$;

comment on function public.is_active_trainer_of is 'True if the calling user is the trainer half of an active, non-expired connection to target_user_id. Gates every trainer WRITE policy added in this migration — read access is still can_view_profile_content()''s job.';

-- ── Routines: trainer can create/edit a student's routines, never delete.
-- The existing "Users can manage their own routines" ALL policy already
-- covers the owner (including their own delete) and is left untouched.
create policy "Trainer can create routines for their student"
  on public.routines for insert
  with check (public.is_active_trainer_of(user_id));

create policy "Trainer can edit routines for their student"
  on public.routines for update
  using (public.is_active_trainer_of(user_id))
  with check (public.is_active_trainer_of(user_id));

create policy "Trainer can create exercises within student's routines"
  on public.routine_exercises for insert
  with check (
    exists (
      select 1 from public.routines r
      where r.id = routine_exercises.routine_id
        and public.is_active_trainer_of(r.user_id)
    )
  );

create policy "Trainer can edit exercises within student's routines"
  on public.routine_exercises for update
  using (
    exists (
      select 1 from public.routines r
      where r.id = routine_exercises.routine_id
        and public.is_active_trainer_of(r.user_id)
    )
  )
  with check (
    exists (
      select 1 from public.routines r
      where r.id = routine_exercises.routine_id
        and public.is_active_trainer_of(r.user_id)
    )
  );

-- ── user_settings: trainer can update the ROTATION fields only (rotations,
-- active_rotation_id, schedule, schedule_pos). Never insert (the row is
-- created lazily by the student's own device on first save — a trainer
-- editing a student who has never opened the app has nothing to attach
-- to yet, and creating one from the trainer side risks minting a row with
-- wrong defaults) and never delete.
--
-- RLS alone is row-level, not column-level, so the UPDATE policy below
-- cannot by itself stop a trainer write from also touching theme/accent/
-- lang/motiv_enabled/last_notes. The trigger further down is the actual
-- column guard; the policy only decides WHO may attempt the update at all.
create policy "Trainer can update student's rotation fields"
  on public.user_settings for update
  using (public.is_active_trainer_of(user_id))
  with check (public.is_active_trainer_of(user_id));

create or replace function public.guard_trainer_user_settings_update()
returns trigger
language plpgsql
as $$
begin
  -- The owner's own "manage own settings" ALL policy is what let a
  -- self-update through; this guard only needs to fire for the OTHER case
  -- this table now permits — a trainer editing someone else's row.
  if auth.uid() <> new.user_id then
    if new.theme is distinct from old.theme
      or new.accent is distinct from old.accent
      or new.motiv_enabled is distinct from old.motiv_enabled
      or new.lang is distinct from old.lang
      or new.last_notes is distinct from old.last_notes
    then
      raise exception 'Trainers can only edit a student''s rotation and schedule fields.';
    end if;
  end if;
  return new;
end;
$$;

comment on function public.guard_trainer_user_settings_update is 'Column-level backstop for the trainer UPDATE policy above: RLS can only gate which ROWS a trainer may touch, not which columns, so this trigger rejects any trainer-initiated update that changes anything besides rotations/active_rotation_id/schedule/schedule_pos.';

create trigger user_settings_guard_trainer_columns
  before update on public.user_settings
  for each row
  execute function public.guard_trainer_user_settings_update();

-- Client-side pairing for the above: before saving, the trainer's app reads
-- the student's user_settings.updated_at and sends it back as an
-- `.eq('updated_at', ...)` condition on the update call. If the student's
-- own device has synced anything in between, updated_at has moved and the
-- conditional update matches zero rows — the client detects that (an empty
-- returned row set) and surfaces "this student's data changed, reload and
-- try again" instead of silently overwriting a newer local change. No
-- schema needed for this half — user_settings already has updated_at,
-- auto-maintained by the existing set_updated_at trigger.

-- ── Workout logs: trainer can log a NEW session for their student (Live
-- Session), and edit — but never delete — a session they logged themselves.
-- logged_by_trainer_id is what makes both the UI tag ("logged by trainer")
-- and the edit-scoping below possible; null for every session a student
-- logs on their own device, exactly as today.
alter table public.workout_logs
  add column logged_by_trainer_id uuid references auth.users (id) on delete set null;

comment on column public.workout_logs.logged_by_trainer_id is 'Non-null only when a connected trainer logged this session on the student''s behalf via Live Session. Null for every self-logged session — the existing, unchanged default for all history up to now.';

create policy "Trainer can log a session for their student"
  on public.workout_logs for insert
  with check (
    public.is_active_trainer_of(user_id)
    and logged_by_trainer_id = auth.uid()
  );

create policy "Trainer can edit sessions they logged for their student"
  on public.workout_logs for update
  using (logged_by_trainer_id = auth.uid() and public.is_active_trainer_of(user_id))
  with check (logged_by_trainer_id = auth.uid() and public.is_active_trainer_of(user_id));

create policy "Trainer can add exercises to a session they logged"
  on public.workout_log_exercises for insert
  with check (
    exists (
      select 1 from public.workout_logs wl
      where wl.id = workout_log_exercises.log_id
        and wl.logged_by_trainer_id = auth.uid()
        and public.is_active_trainer_of(wl.user_id)
    )
  );

create policy "Trainer can edit exercises in a session they logged"
  on public.workout_log_exercises for update
  using (
    exists (
      select 1 from public.workout_logs wl
      where wl.id = workout_log_exercises.log_id
        and wl.logged_by_trainer_id = auth.uid()
        and public.is_active_trainer_of(wl.user_id)
    )
  )
  with check (
    exists (
      select 1 from public.workout_logs wl
      where wl.id = workout_log_exercises.log_id
        and wl.logged_by_trainer_id = auth.uid()
        and public.is_active_trainer_of(wl.user_id)
    )
  );

create policy "Trainer can add sets to a session they logged"
  on public.workout_log_sets for insert
  with check (
    exists (
      select 1 from public.workout_log_exercises wle
      join public.workout_logs wl on wl.id = wle.log_id
      where wle.id = workout_log_sets.log_exercise_id
        and wl.logged_by_trainer_id = auth.uid()
        and public.is_active_trainer_of(wl.user_id)
    )
  );

create policy "Trainer can edit sets in a session they logged"
  on public.workout_log_sets for update
  using (
    exists (
      select 1 from public.workout_log_exercises wle
      join public.workout_logs wl on wl.id = wle.log_id
      where wle.id = workout_log_sets.log_exercise_id
        and wl.logged_by_trainer_id = auth.uid()
        and public.is_active_trainer_of(wl.user_id)
    )
  )
  with check (
    exists (
      select 1 from public.workout_log_exercises wle
      join public.workout_logs wl on wl.id = wle.log_id
      where wle.id = workout_log_sets.log_exercise_id
        and wl.logged_by_trainer_id = auth.uid()
        and public.is_active_trainer_of(wl.user_id)
    )
  );

-- ── last_weights / all_time_prs: Live Session needs to keep these caches
-- correct for the student too (same computation finishWorkout() already
-- does locally, run against the student's remote data instead). These are
-- whole-row upserts on the student's own periodic sync, same as
-- user_settings — a trainer write here can, in principle, race a
-- same-moment sync from the student's own device. Unlike the rotation
-- edit above, this isn't a new hazard: two of the STUDENT's OWN devices
-- syncing minutes apart already have to tolerate this today, so Live
-- Session is just one more legitimate writer in the same existing model,
-- not a new class of risk — no extra guard added here.
create policy "Trainer can log a PR for their student"
  on public.all_time_prs for insert
  with check (public.is_active_trainer_of(user_id));

create policy "Trainer can update a PR for their student"
  on public.all_time_prs for update
  using (public.is_active_trainer_of(user_id))
  with check (public.is_active_trainer_of(user_id));

create policy "Trainer can log a last-weight entry for their student"
  on public.last_weights for insert
  with check (public.is_active_trainer_of(user_id));

create policy "Trainer can update a last-weight entry for their student"
  on public.last_weights for update
  using (public.is_active_trainer_of(user_id))
  with check (public.is_active_trainer_of(user_id));

-- ── pr_events: a PR the trainer logs for a student should notify that
-- student's followers exactly like a self-logged one — same table, same
-- visibility rule, the only new thing is who is allowed to insert on the
-- student's behalf.
create policy "Trainer can log a PR event for their student"
  on public.pr_events for insert
  with check (public.is_active_trainer_of(user_id));

-- ── Assertions: confirm no existing student/trainer data was touched.
do $$
declare
  bad_count integer;
begin
  select count(*) into bad_count from public.workout_logs where logged_by_trainer_id is not null;
  if bad_count <> 0 then
    raise exception 'Expected every existing workout_logs row to have logged_by_trainer_id null — % did not.', bad_count;
  end if;
end $$;
