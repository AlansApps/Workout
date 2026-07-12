-- ============================================================================
-- Profiles
-- ============================================================================
-- One row per authenticated user, mirroring auth.users with app-specific
-- fields. A trigger keeps this table populated automatically whenever a new
-- user signs up, so the app never has to create this row itself.
--
-- Identity follows the Instagram model: `username` is the unique @handle
-- (used for login-adjacent lookups and shown as "@handle" in the UI), while
-- `full_name` is a free-text display name that doesn't have to be unique.
-- OAuth signups (Google, etc.) won't have a username yet on first login —
-- the app must prompt for one before the profile is considered complete.
--
-- `is_admin`, `verified` and `subscription_tier` exist now so the schema
-- doesn't need a breaking migration later, even though no login flow, admin
-- account, or paid tier exists yet.
-- ============================================================================

create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  username           text unique check (username ~ '^[a-z0-9._]{3,30}$'),
  full_name          text check (char_length(full_name) <= 100),
  is_admin           boolean not null default false,
  verified           boolean not null default false,
  subscription_tier  text not null default 'free' check (subscription_tier in ('free', 'premium')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.profiles is 'One row per app user, extending auth.users with app-specific fields.';
comment on column public.profiles.username is 'Unique @handle: lowercase letters, digits, dots and underscores, 3-30 chars. Nullable because OAuth signups don''t have one until the app''s onboarding step assigns it.';
comment on column public.profiles.full_name is 'Free-text display name (e.g. "Alan Albrecht"). Not unique, unlike username.';
comment on column public.profiles.is_admin is 'True only for the app owner''s account. Admins always get subscription_tier = premium behavior for free, enforced in application logic.';
comment on column public.profiles.verified is 'Shows a verified badge next to the username, similar to a social network checkmark.';

-- Keep updated_at current on every change, so we can tell at a glance how
-- fresh a profile row is without relying on client-supplied timestamps.
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- Automatically create a profile row the moment a user signs up through
-- Supabase Auth, so the app can always assume profiles.id = auth.uid() exists.
--
-- `username` is left null for OAuth signups (Google doesn't provide one) —
-- the app's onboarding flow must detect a null username and prompt the user
-- to pick a handle before treating the profile as complete. `full_name`
-- falls back to whatever the provider hands us (Google supplies "full_name"
-- or "name"; email/password signup can pass "full_name" as signup metadata).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
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
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ── Row Level Security ──
-- Every user can read and update only their own profile row. Nobody can
-- insert or delete profile rows directly — that only happens via the trigger
-- above (insert) or cascading from auth.users deletion (delete).
alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);
