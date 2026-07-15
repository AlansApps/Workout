-- ============================================================================
-- Fix follows INSERT policy — was checking a table it couldn't read
-- ============================================================================
-- The original INSERT policy's WITH CHECK queried public.profiles directly
-- to test the target's is_private flag. But public.profiles only allows a
-- user to SELECT their own row (that's the whole reason public_profiles
-- exists as a separate view) — so from the follower's perspective, that
-- subquery could never see the target's row and always returned no rows,
-- meaning `status = 'accepted'` inserts were rejected 100% of the time,
-- even against a genuinely public target. Verified live: an end-to-end
-- test (two throwaway accounts) showed a straightforward "follow a public
-- account" never succeeded.
--
-- Fix: read the privacy flag through public.public_profiles instead —
-- the view is created `with (security_invoker = false)`, so it runs with
-- its owner's privileges and can see every row, while still only ever
-- exposing the safe whitelisted columns (id, username, full_name,
-- verified, subscription_tier, is_private). Same visibility problem,
-- same class of fix as is_username_allowed() and can_view_profile_content()
-- before it — a plain policy body runs under the CALLING user's RLS view,
-- which can quietly return an empty/wrong result instead of erroring.
-- ============================================================================

drop policy "Users can create their own follow requests" on public.follows;

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
