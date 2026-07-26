-- ============================================================================
-- Per-exercise PR visibility (replaces the blanket show_prs toggle)
-- ============================================================================
-- Alan's actual ask was finer-grained than the show_prs boolean shipped
-- moments earlier: choose WHICH tracked exercises' PRs appear on the
-- profile (e.g. only Squat/Deadlift/Bench Press), not an all-or-nothing
-- switch. This column subsumes show_prs entirely — hiding every tracked
-- exercise has the exact same visible effect the old "off" state did —
-- so show_prs is dropped rather than left behind as dead, confusing
-- state sitting next to it.
--
-- Destructive part (drop column) is guarded by an assertion, per the
-- project convention: abort rather than silently discard if anyone
-- actually flipped show_prs off in the brief window since it shipped.
-- ============================================================================

do $$
declare
  cnt integer;
begin
  select count(*) into cnt from public.profiles where show_prs = false;
  if cnt <> 0 then
    raise exception 'Expected no profile to have toggled show_prs off yet (feature shipped moments ago) — % found; migrate their preference into hidden_pr_exercise_ids before dropping the column', cnt;
  end if;
end $$;

alter table public.profiles
  add column hidden_pr_exercise_ids text[] not null default '{}';

-- The view's trailing column is being renamed (show_prs -> hidden_pr_
-- exercise_ids), not just appended to — CREATE OR REPLACE VIEW only
-- allows adding new trailing columns, not renaming/removing an existing
-- one (confirmed live: "cannot change name of view column show_prs to
-- hidden_pr_exercise_ids"). That forces an actual DROP + recreate, which
-- in turn requires CASCADE, since follows' "Users can create their own
-- follow requests" INSERT policy reads through this view (confirmed
-- live: dropping the column errored on that dependency first). Recreated
-- verbatim below from 20260715000005_fix_follows_insert_policy.sql —
-- it never referenced show_prs, only is_private, so it's unaffected by
-- what actually changed here.
drop view public.public_profiles cascade;

create view public.public_profiles
with (security_invoker = false)
as
select id, username, full_name, verified, subscription_tier, is_private, equipped_insignia, hidden_pr_exercise_ids
from public.profiles;

grant select on public.public_profiles to authenticated;

create policy "Users can create their own follow requests"
  on public.follows for insert
  with check (
    auth.uid() = follower_id
    and (
      status = 'pending'
      or (
        status = 'accepted'
        and exists (
          select 1 from public.public_profiles
          where public_profiles.id = following_id and public_profiles.is_private = false
        )
      )
    )
  );

alter table public.profiles
  drop column show_prs;
