-- ============================================================================
-- get_session_day_counts — batched distinct-day session counts
-- ============================================================================
-- Powers the tier icon shown next to each person in the Interactions feed
-- ("X is now following you"). Without this, showing N followers' tiers
-- would mean N separate queries against workout_logs; this does it in one
-- round trip for a whole batch of user ids.
--
-- SECURITY DEFINER so it can read across workout_logs regardless of the
-- caller's own RLS visibility into those rows (same reasoning as
-- can_view_profile_content) — but it only ever returns an aggregate COUNT,
-- never any row content (no routine names, no weights), so this is safe
-- to expose broadly: the workout count is already meant to be public-facing
-- profile info, same as the "N Workouts" stat.
-- ============================================================================

create or replace function public.get_session_day_counts(user_ids uuid[])
returns table(user_id uuid, day_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select wl.user_id, count(distinct date(wl.performed_at)) as day_count
  from public.workout_logs wl
  where wl.user_id = any(user_ids)
  group by wl.user_id;
$$;

comment on function public.get_session_day_counts is 'Batched distinct-training-day counts for a list of user ids — aggregate only, never exposes individual log rows.';
