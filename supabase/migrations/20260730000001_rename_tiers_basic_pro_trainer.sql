-- ============================================================================
-- Rework the tier model: basic / pro / trainer / trainer_pro
-- ============================================================================
-- Alan's spec (2026-07-30). The tiers are two INDEPENDENT capabilities, not
-- one ladder — which is why there are four names rather than three:
--
--                    Trainer tab?     Scan feature?
--   basic                 no               no       <- everyone
--   pro                   no              yes
--   trainer              yes               no
--   trainer_pro          yes              yes       <- Alan
--
-- "trainer" grants the bottom Trainer tab. "pro" grants the video scan /
-- form-diagnosis feature, which does not exist yet — the tier is defined
-- now so the plumbing is in place, but nothing gates on it today.
--
-- Renames from the old vocabulary: free -> basic, member -> pro. 'trainer'
-- keeps its name. 'trainer_pro' is new.
--
-- IMPORTANT correction to an earlier assumption of mine: 'member' was never
-- the early-supporter grant. The first 100 signups received the OG MEMBER
-- INSIGNIA regardless of which plan they were on — that is a separate thing
-- entirely and is not touched here. Verified against production before
-- writing this: all 4 existing profiles are on 'free', nobody holds 'member'
-- or 'trainer', so no real user is being moved off a tier they were given.
--
-- Insignia rules, both changed:
--   • trainer insignia          -> anyone on 'trainer' OR 'trainer_pro'
--   • early_supporter insignia  -> the first 100 people ever to reach ANY
--                                  paid tier ('pro', 'trainer', 'trainer_pro'),
--                                  hard-capped at 100 forever. Existing
--                                  holders keep it regardless.
-- ============================================================================

-- ── 1. Widen the constraint before touching data, or the UPDATEs below
-- would violate the old one mid-flight.
alter table public.profiles drop constraint profiles_subscription_tier_check;

alter table public.profiles
  alter column subscription_tier set default 'basic';


-- ── 2. Rewrite the insignia trigger BEFORE migrating data, so the data
-- migration below is evaluated under the new rules rather than the old
-- ones (setting Alan to trainer_pro should grant the trainer insignia).
create or replace function public.grant_tier_upgrade_insignias()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  supporter_count integer;
begin
  -- Trainer insignia: both trainer-capable tiers qualify. Checked as
  -- "is now trainer-capable and wasn't before" so re-saving an unrelated
  -- profile field never re-triggers it.
  if new.subscription_tier in ('trainer','trainer_pro')
     and (old.subscription_tier is null
          or old.subscription_tier not in ('trainer','trainer_pro')) then
    insert into public.user_insignias (user_id, insignia_id)
    values (new.id, 'trainer')
    on conflict do nothing;
  end if;

  -- Early Supporter: first 100 people ever to reach any PAID tier. Counting
  -- rows already granted (rather than counting paying profiles) is what makes
  -- the cap permanent — once 100 badges exist the branch can never grant
  -- another, even if those users later downgrade or delete their accounts.
  if new.subscription_tier in ('pro','trainer','trainer_pro')
     and (old.subscription_tier is null
          or old.subscription_tier not in ('pro','trainer','trainer_pro')) then
    select count(*) into supporter_count
      from public.user_insignias where insignia_id = 'early_supporter';
    if supporter_count < 100 then
      insert into public.user_insignias (user_id, insignia_id)
      values (new.id, 'early_supporter')
      on conflict do nothing;
    end if;
  end if;

  return new;
end;
$$;


-- ── 3. Migrate the data.
-- The privileged-field guard raises on any subscription_tier change from a
-- non-service_role connection. In a migration auth.role() is NULL, and
-- `true and (NULL <> 'service_role')` evaluates to NULL so the guard would
-- not actually fire — but relying on three-valued-logic for whether a
-- security control blocks you is exactly the kind of thing that breaks
-- silently later. Disabled explicitly instead, and re-enabled below.
alter table public.profiles disable trigger profiles_protect_privileged_fields;

update public.profiles set subscription_tier = 'basic'   where subscription_tier = 'free';
update public.profiles set subscription_tier = 'pro'     where subscription_tier = 'member';

-- Alan is the sole admin and gets the maximum tier permanently, per the
-- standing rule that the owner account always has full visibility of every
-- feature. Keyed on is_admin rather than a hardcoded uuid or username so it
-- stays correct if either ever changes.
update public.profiles set subscription_tier = 'trainer_pro' where is_admin = true;

alter table public.profiles enable trigger profiles_protect_privileged_fields;


-- ── 4. Re-apply the constraint, now over the new vocabulary only.
alter table public.profiles add constraint profiles_subscription_tier_check
  check (subscription_tier in ('basic','pro','trainer','trainer_pro'));


-- ── 5. Assertions. Abort loudly rather than leave the tier table in a
-- state Alan did not ask for.
do $$
declare
  stragglers integer;
  admin_tier text;
begin
  -- Every non-admin must be on basic. If production turns out to hold a
  -- paying user I did not see when checking, this stops the migration
  -- instead of silently promoting or demoting them.
  select count(*) into stragglers
    from public.profiles
    where is_admin is not true and subscription_tier <> 'basic';
  if stragglers <> 0 then
    raise exception 'Expected every non-admin profile to end on basic — % are not. Resolve manually before re-running.', stragglers;
  end if;

  select subscription_tier into admin_tier
    from public.profiles where is_admin = true limit 1;
  if admin_tier is distinct from 'trainer_pro' then
    raise exception 'Admin account should be trainer_pro, found %', coalesce(admin_tier,'(no admin row)');
  end if;
end $$;


-- ── 6. Backfill the trainer insignia for anyone already trainer-capable.
-- The trigger in step 2 only fires on UPDATE, and step 3's update to Alan
-- did fire it — this is belt-and-braces for any row that somehow arrived at
-- a trainer tier without passing through that path.
insert into public.user_insignias (user_id, insignia_id)
select id, 'trainer' from public.profiles
where subscription_tier in ('trainer','trainer_pro')
on conflict do nothing;
