-- ============================================================================
-- Public profile visibility
-- ============================================================================
-- Two things this migration adds:
--
-- 1. public_profiles — a VIEW exposing only the columns safe to show to
--    other users (username, full_name, verified, subscription_tier,
--    is_private), never email/has_password. profiles itself stays locked to
--    "only your own row" — RLS is row-level, not column-level, so simply
--    adding a broader SELECT policy on the base table would let anyone
--    query the REST API directly with select=* and read every user's
--    email. A view created without security_invoker (the Postgres default
--    since PG15) runs with its OWNER's privileges rather than the
--    caller's, so it can read across the restrictive base-table RLS while
--    only ever exposing the whitelisted columns — the caller never gets
--    the option to select more than that.
--
-- 2. can_view_profile_content(uuid) — a helper used by new SELECT policies
--    on routines/user_settings/workout_logs (and their child tables) so a
--    user's Program/Log content is readable by others when either the
--    profile is public, or the viewer has an accepted follow relationship
--    to them. SECURITY DEFINER because it needs to read profiles/follows
--    reliably regardless of the calling user's own row-level access to
--    those tables — the same fix already applied to is_username_allowed()
--    for the same underlying reason (a plain function body runs with the
--    caller's RLS view, which can return an empty/wrong result rather than
--    an error, silently breaking the check).
-- ============================================================================

create view public.public_profiles
with (security_invoker = false)
as
select id, username, full_name, verified, subscription_tier, is_private
from public.profiles;

comment on view public.public_profiles is 'Read-only public subset of profiles — never exposes email or has_password. Use this (not profiles directly) whenever displaying another user''s identity.';

grant select on public.public_profiles to authenticated;

create or replace function public.can_view_profile_content(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = target_user_id
      and (
        p.is_private = false
        or exists (
          select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.following_id = target_user_id
            and f.status = 'accepted'
        )
      )
  );
$$;

comment on function public.can_view_profile_content is 'True if target_user_id''s Program/Log content should be visible to the calling user: their own data, a public profile, or an accepted follow. Used by additional SELECT-only policies below — never touches the existing owner-only ALL policies that gate writes.';

-- ── Routines — additive SELECT policy, existing "manage own" ALL policy
--    is untouched so only the owner can still insert/update/delete. ──
create policy "Others can view routines when public.can_view_profile_content"
  on public.routines for select
  using (auth.uid() = user_id or public.can_view_profile_content(user_id));

create policy "Others can view exercises within visible routines"
  on public.routine_exercises for select
  using (
    exists (
      select 1 from public.routines r
      where r.id = routine_exercises.routine_id
        and (r.user_id = auth.uid() or public.can_view_profile_content(r.user_id))
    )
  );

-- ── Schedule (rotation + position) lives in user_settings ──
create policy "Others can view schedule when public.can_view_profile_content"
  on public.user_settings for select
  using (auth.uid() = user_id or public.can_view_profile_content(user_id));

-- ── Workout log history, for the Log tab ──
create policy "Others can view workout logs when public.can_view_profile_content"
  on public.workout_logs for select
  using (auth.uid() = user_id or public.can_view_profile_content(user_id));

create policy "Others can view exercises within visible workout logs"
  on public.workout_log_exercises for select
  using (
    exists (
      select 1 from public.workout_logs wl
      where wl.id = workout_log_exercises.log_id
        and (wl.user_id = auth.uid() or public.can_view_profile_content(wl.user_id))
    )
  );

create policy "Others can view sets within visible workout logs"
  on public.workout_log_sets for select
  using (
    exists (
      select 1 from public.workout_log_exercises wle
      join public.workout_logs wl on wl.id = wle.log_id
      where wle.id = workout_log_sets.log_exercise_id
        and (wl.user_id = auth.uid() or public.can_view_profile_content(wl.user_id))
    )
  );
