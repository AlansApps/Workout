-- ============================================================================
-- Ping blocking — opt out of receiving pings, which also stops you sending
-- ============================================================================
-- Alan's spec: a switch in Settings to block incoming pings, and "if you
-- block them, you can't send them either". That reciprocity is the point —
-- it makes the feature symmetric (you're either in the ping system or out
-- of it) instead of a free one-way mute that lets someone keep nudging
-- people who can't nudge back.
--
-- Enforced HERE, in the INSERT policy, not in the app. A UI-only check
-- would be bypassable by anyone with the anon key and a fetch() call —
-- which is every user, since the key ships in the page. The client-side
-- hiding of the Ping button is convenience, not the control.
--
-- Column polarity: `pings_blocked`, defaulting to false, so it maps 1:1
-- onto the Settings switch (on = blocked) exactly the way is_private
-- already does on the row directly above it, and so every existing profile
-- keeps pings on with no backfill.
-- ============================================================================

alter table public.profiles
  add column pings_blocked boolean not null default false;

comment on column public.profiles.pings_blocked is 'User opted out of pings entirely: they receive none, and the pings INSERT policy also refuses to let them send any.';

-- Expose it on the read-side view so the app can hide the Ping button on a
-- profile that won't accept one. This is a pure trailing-column addition,
-- so CREATE OR REPLACE is legal here — no DROP ... CASCADE, and the follows
-- INSERT policy that reads through this view is left untouched (unlike
-- 20260727000001, which had to rename a column and so could not).
create or replace view public.public_profiles
with (security_invoker = false)
as
select id, username, full_name, verified, subscription_tier, is_private, equipped_insignia, hidden_pr_exercise_ids, pings_blocked
from public.profiles;

grant select on public.public_profiles to authenticated;

-- Rewrite the INSERT policy. public_profiles is a security_invoker = false
-- view, so reading it inside a policy does not recurse through profiles'
-- own RLS — the same trick the follows INSERT policy already relies on to
-- read is_private.
--
-- Note this deliberately does NOT restrict pings to people you follow.
-- That was never the rule and isn't what was asked for; the only new gate
-- is the two blocked flags.
drop policy "Users can send their own pings" on public.pings;

create policy "Users can send their own pings"
  on public.pings for insert
  with check (
    auth.uid() = sender_id
    -- The recipient has not opted out.
    and exists (
      select 1 from public.public_profiles pp
      where pp.id = pings.recipient_id and pp.pings_blocked = false
    )
    -- ...and neither has the sender. Blocking receipt blocks sending.
    and exists (
      select 1 from public.public_profiles pp
      where pp.id = pings.sender_id and pp.pings_blocked = false
    )
  );

-- Existing pings are left alone. Turning the switch on stops future ones;
-- it is not a retroactive delete of history the recipient already saw.
