-- ============================================================================
-- Membership tiers (Free / Member / Trainer) + privileged-field protection
-- ============================================================================
-- Replaces the placeholder 'free'/'premium' pair (never actually used —
-- 'premium' was never granted to any account) with the real 3-tier model:
--   free    — current default, no cost. Eventually time-limited (3 months)
--             once a real paywall exists; unlimited for everyone for now.
--   member  — USD 0.99/mo once billing exists. No payment flow yet — this
--             migration only adds the tier value and the automation that
--             should already be correct the moment an upgrade path exists.
--   trainer — USD 5.99/mo once billing exists. Unlocks the Trainer nav tab
--             (see index.html's getEffectiveTier()/updateTrainerNavVisibility()).
--
-- Three pieces:
--   1. Widen the subscription_tier check constraint.
--   2. Guard subscription_tier/is_admin so only a service-role connection
--      (a future billing webhook, or this migration itself) can change
--      them — today's RLS update policy has no column restriction at all,
--      so any signed-in user could otherwise grant themselves Trainer
--      access for free the moment that tier starts gating a real feature.
--   3. Auto-grant insignias on tier upgrade: the first 100 accounts ever
--      to reach Member get 'early_supporter' (mirrors the existing
--      first-100 'og_member' signup rule in handle_new_user()); every
--      account that reaches Trainer gets the 'trainer' insignia, uncapped.
-- ============================================================================

-- ── 1. Widen the tier constraint ──
do $$
declare
  cnt integer;
begin
  select count(*) into cnt from public.profiles where subscription_tier = 'premium';
  if cnt <> 0 then
    raise exception 'Expected 0 profiles on the unused premium tier before dropping it, found %', cnt;
  end if;
end $$;

alter table public.profiles drop constraint profiles_subscription_tier_check;
alter table public.profiles add constraint profiles_subscription_tier_check
  check (subscription_tier in ('free', 'member', 'trainer'));

-- ── 2. Protect subscription_tier and is_admin from self-service updates ──
-- auth.role() reflects the JWT's role claim: 'authenticated' for a normal
-- signed-in client request, 'service_role' for anything using the service
-- key (a future billing webhook, or a migration/admin script like this
-- one running with elevated credentials). Every other column on this row
-- (username, full_name, is_private, equipped_insignia, etc.) is untouched
-- by this guard — only these two privileged fields are locked down.
create or replace function public.protect_privileged_profile_fields()
returns trigger
language plpgsql
as $$
begin
  if (new.subscription_tier is distinct from old.subscription_tier
      or new.is_admin is distinct from old.is_admin)
     and auth.role() <> 'service_role' then
    raise exception 'subscription_tier and is_admin cannot be changed directly by users';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_privileged_fields
  before update on public.profiles
  for each row
  execute function public.protect_privileged_profile_fields();

-- ── 3a. First 100 Members ever get 'early_supporter' ──
create or replace function public.grant_tier_upgrade_insignias()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  supporter_count integer;
begin
  if new.subscription_tier = 'member' and old.subscription_tier is distinct from 'member' then
    select count(*) into supporter_count from public.user_insignias where insignia_id = 'early_supporter';
    if supporter_count < 100 then
      insert into public.user_insignias (user_id, insignia_id) values (new.id, 'early_supporter')
      on conflict do nothing;
    end if;
  end if;

  if new.subscription_tier = 'trainer' and old.subscription_tier is distinct from 'trainer' then
    insert into public.user_insignias (user_id, insignia_id) values (new.id, 'trainer')
    on conflict do nothing;
  end if;

  return new;
end;
$$;

-- AFTER UPDATE, not BEFORE: protect_privileged_profile_fields (a BEFORE
-- trigger) raises an exception and aborts the whole statement if an
-- unauthorized caller tries to change subscription_tier, which means this
-- trigger simply never runs for a rejected update — no ordering race
-- between the two to worry about.
create trigger profiles_grant_tier_upgrade_insignias
  after update on public.profiles
  for each row
  execute function public.grant_tier_upgrade_insignias();

-- ── Alan's own account: is_admin (→ full Trainer-tier behavior for free,
--    per this column's existing comment) plus both insignias directly,
--    same "one specific account, not a general rule" treatment as the
--    Founder backfill. Session-count tier badges are NOT touched here —
--    those stay fully computed client-side from workoutLog, same rule
--    for every account including this one.
update public.profiles set is_admin = true where username = 'alan';

insert into public.user_insignias (user_id, insignia_id)
select id, 'trainer' from public.profiles where username = 'alan'
on conflict do nothing;

insert into public.user_insignias (user_id, insignia_id)
select id, 'early_supporter' from public.profiles where username = 'alan'
on conflict do nothing;
