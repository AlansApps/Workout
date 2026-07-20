-- ============================================================================
-- Insignias: tiers + special badges, unlock-and-equip
-- ============================================================================
-- Replaces the old "always show your single highest tier" behavior with a
-- permanent unlock record per (user, insignia) plus one explicitly chosen
-- "equipped" insignia. The 7 tiers already existed as a client-only concept
-- (TIERS/getTier() in index.html); this is the first time they're tracked
-- server-side. Four new special (non-tier) insignias are added alongside
-- them: Founder, Trainer, OG Member, Early Supporter.
--
-- Icons and display names for the tiers live client-side (TIER_ICONS) same
-- as before — this table only needs enough identity to unlock/equip against,
-- not full presentation data.
-- ============================================================================

create table public.insignias (
  id          text primary key,
  name        text not null,
  category    text not null check (category in ('tier', 'special')),
  sort_order  smallint not null default 0
);

comment on table public.insignias is 'Catalog of every tier and special badge. Icon/color/copy stays client-side (TIER_ICONS etc.) — this table exists so unlocks and the equipped choice have something to reference.';

insert into public.insignias (id, name, category, sort_order) values
  ('tier_rookie',     'Rookie',     'tier', 1),
  ('tier_regular',    'Regular',    'tier', 2),
  ('tier_dedicated',  'Dedicated',  'tier', 3),
  ('tier_beast',      'Beast',      'tier', 4),
  ('tier_veteran',    'Veteran',    'tier', 5),
  ('tier_elite',      'Elite',      'tier', 6),
  ('tier_legend',     'Legend',     'tier', 7),
  ('founder',         'Founder',        'special', 100),
  ('trainer',         'Trainer',        'special', 101),
  ('og_member',       'OG Member',      'special', 102),
  ('early_supporter', 'Early Supporter','special', 103);

-- ── Who has unlocked what ──
-- Fully server-granted, read-only to clients: every row here comes from
-- this migration's backfill or the new-user trigger below, never from a
-- client insert. Tiers are NOT tracked in this table at all — they're
-- always computed fresh client-side from workoutLog (see getUnlockedTiers()
-- in index.html), so there's nothing for a client to write here. No INSERT
-- policy is granted on purpose: if per-tier syncing is ever added, it needs
-- its own policy that validates the specific insignia_id was actually
-- earned, not a blanket auth.uid()=user_id check.
create table public.user_insignias (
  user_id      uuid not null references auth.users (id) on delete cascade,
  insignia_id  text not null references public.insignias (id) on delete cascade,
  unlocked_at  timestamptz not null default now(),
  primary key (user_id, insignia_id)
);

comment on table public.user_insignias is 'Permanent unlock record for special (non-tier) badges — Founder/Trainer/OG Member/Early Supporter. Every row is server-written (backfill or the new-user trigger); no client insert path exists.';

create index user_insignias_user_id_idx on public.user_insignias (user_id);

-- Covers the count(*) ... where insignia_id = 'og_member' check that runs
-- inside handle_new_user() on every single signup, forever (not just while
-- the first-100 window is open) — without this it's a sequential scan on
-- every new account creation.
create index user_insignias_insignia_id_idx on public.user_insignias (insignia_id);

alter table public.user_insignias enable row level security;

create policy "Users can view their own unlocked insignias"
  on public.user_insignias for select
  using (auth.uid() = user_id);

-- Deliberately no INSERT/UPDATE/DELETE policy — see the table comment
-- above. Writes only ever happen via SECURITY DEFINER functions
-- (handle_new_user()) or migrations, both of which bypass RLS.

-- ── Which one is currently shown ──
alter table public.profiles
  add column equipped_insignia text references public.insignias (id) on delete set null;

comment on column public.profiles.equipped_insignia is 'Which unlocked insignia this user chose to display. Null = auto-show their highest unlocked tier, matching the pre-insignias behavior.';

-- Expose the new column on the read-only cross-user view — other people's
-- profile pages need to render whichever insignia they've equipped.
create or replace view public.public_profiles
with (security_invoker = false)
as
select id, username, full_name, verified, subscription_tier, is_private, equipped_insignia
from public.profiles;

-- ── OG Member: first 100 accounts ever, one-time cutoff ──
-- Extends the existing new-user trigger rather than adding a second one, so
-- the "first 100" check and the profile-row insert stay atomic with signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  og_count integer;
begin
  insert into public.profiles (id, username, full_name)
  values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    )
  );

  select count(*) into og_count from public.user_insignias where insignia_id = 'og_member';
  if og_count < 100 then
    insert into public.user_insignias (user_id, insignia_id) values (new.id, 'og_member');
  end if;

  return new;
end;
$$;

-- ── Backfill for accounts that already exist ──

-- OG Member, oldest 100 accounts by signup order.
insert into public.user_insignias (user_id, insignia_id, unlocked_at)
select id, 'og_member', created_at
from public.profiles
order by created_at asc
limit 100
on conflict do nothing;

-- Tiers: every threshold each existing user has already crossed, not just
-- their current highest — matches the new "remember everything unlocked"
-- model instead of only the tier they'd see under the old logic.
insert into public.user_insignias (user_id, insignia_id)
select wl.user_id, tiers.insignia_id
from (
  select user_id, count(distinct date(performed_at)) as day_count
  from public.workout_logs
  group by user_id
) wl
cross join (values
  ('tier_rookie',    10),
  ('tier_regular',   25),
  ('tier_dedicated', 50),
  ('tier_beast',     100),
  ('tier_veteran',   250),
  ('tier_elite',     500),
  ('tier_legend',    1000)
) as tiers(insignia_id, threshold)
where wl.day_count >= tiers.threshold
on conflict do nothing;

-- Founder: exactly one account, @alan. Just a notice (not an error) if that
-- handle doesn't exist yet — re-run this insert once it does.
do $$
begin
  if not exists (select 1 from public.profiles where username = 'alan') then
    raise notice 'No profile with username=''alan'' found — Founder not granted yet.';
  end if;
end $$;

insert into public.user_insignias (user_id, insignia_id)
select id, 'founder' from public.profiles where username = 'alan'
on conflict do nothing;

-- ── Assertion ──
do $$
declare
  cnt integer;
begin
  select count(*) into cnt from public.insignias;
  if cnt <> 11 then
    raise exception 'Expected 11 insignias in the catalog, found %', cnt;
  end if;
end $$;
