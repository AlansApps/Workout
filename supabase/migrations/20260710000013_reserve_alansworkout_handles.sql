-- ============================================================================
-- Reserve @AlansWorkout and its close variants for a possible future admin account
-- ============================================================================
-- Alan wants this handle held back rather than claimable by anyone, in case
-- he wants a separate admin identity later (see project_admin_user_requirement
-- in memory — the admin account itself doesn't exist yet, this just protects
-- the name).
--
-- 'alansworkout' (no separator) was already reserved in
-- 20260710000008_username_rules.sql and is caught by the existing
-- per-segment check, since it's a single unbroken word. But compound
-- variants like 'alans.workout' or 'alans_workout' split into TWO valid
-- segments ("alans" + "workout") — and neither word should be globally
-- reserved on its own (that would block huge numbers of legitimate
-- fitness usernames containing "workout"). So this adds a second,
-- separate check to is_username_allowed(): an exact match against the
-- FULL candidate string, for specific compound handles that need to be
-- blocked as a whole rather than word-by-word.
--
-- 'alans-workout' needs no entry at all — usernames can't contain a
-- dash (see the format CHECK constraints in 20260710000001_profiles.sql
-- and 20260710000008_username_rules.sql), so that string can never pass
-- validation in the first place.
-- ============================================================================

insert into public.reserved_usernames (term) values
  ('alanworkout'),
  ('alans.workout'),
  ('alans_workout')
on conflict (term) do nothing;

create or replace function public.is_username_allowed(candidate text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  seg text;
begin
  -- Whole-candidate exact match: for specific reserved handles (e.g.
  -- "alans.workout") that need to be blocked as a complete string,
  -- regardless of internal dot/underscore segmentation.
  if exists (select 1 from public.reserved_usernames where term = candidate) then
    return false;
  end if;

  -- Per-segment exact match: for generic reserved words (profanity,
  -- impersonation terms) blocked wherever they appear as a standalone
  -- segment, without the Scunthorpe substring problem (see
  -- 20260710000011_seed_offensive_terms.sql for why this is exact-match,
  -- not substring).
  foreach seg in array regexp_split_to_array(candidate, '[._]') loop
    if seg <> '' and exists (select 1 from public.reserved_usernames where term = seg) then
      return false;
    end if;
  end loop;

  return true;
end;
$$;
