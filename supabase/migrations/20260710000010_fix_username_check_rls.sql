-- ============================================================================
-- Fix: is_username_allowed() silently allowed everything for anonymous callers
-- ============================================================================
-- Bug found in manual testing: is_username_allowed() is `language sql`
-- (not security definer), so it runs with the CALLING role's permissions.
-- The reserved_usernames RLS policy only granted SELECT to `authenticated`
-- — but the client calls this function from the sign-up screen, before
-- the user has a session, as the `anon` role. RLS silently returned zero
-- rows for that role, so "not exists (... reserved match ...)" was always
-- true and the check passed every username, reserved or not.
--
-- Fix: make the function SECURITY DEFINER so it always sees the full
-- reserved_usernames table regardless of caller, which is correct here —
-- the table holds no sensitive data, it's just a public blocklist, so
-- there's no actual permission boundary being bypassed.
-- ============================================================================

create or replace function public.is_username_allowed(candidate text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.reserved_usernames
    where candidate ilike '%' || term || '%'
  );
$$;
