-- ============================================================================
-- PR visibility opt-out
-- ============================================================================
-- Lets an account hide its PRs tab from other viewers without going fully
-- private — the rest of the profile (Program, Log, follow) is unaffected.
-- Purely a presentation choice, not a new privacy boundary: other users'
-- clients already receive this account's raw workout_logs rows once
-- can_view_profile_content() allows viewing at all (the Log tab already
-- shows the same underlying sessions), so there is nothing left to protect
-- at the RLS layer here — this only decides whether the derived PRs ledger
-- gets rendered from that same data.
--
-- Two pieces, both additive:
--   1. profiles.show_prs — new column, defaults to true (today's behavior
--      for every existing account is unchanged).
--   2. public_profiles view — extended to expose it, same pattern as every
--      other column already surfaced there (is_private, equipped_insignia).
-- ============================================================================

alter table public.profiles
  add column show_prs boolean not null default true;

create or replace view public.public_profiles
with (security_invoker = false)
as
select id, username, full_name, verified, subscription_tier, is_private, equipped_insignia, show_prs
from public.profiles;
