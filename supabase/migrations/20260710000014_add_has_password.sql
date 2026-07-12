-- ============================================================================
-- Add profiles.has_password — Instagram-style "add/change password"
-- ============================================================================
-- Powers a "Set a Password" / "Change Password" row in My Account, so a
-- Google-only account can also gain email+password login (matching how
-- Instagram lets you add a password later even if you signed up via
-- Facebook). Supabase's auth.users has no clean, RLS-readable signal for
-- "does this user have a password" when manual identity linking is off
-- (it is, in this project) — updateUser({password}) sets the password
-- hash directly on auth.users without adding an 'email' entry to
-- app_metadata.providers, so that array can't be used to detect this.
-- This column is the app's own explicit tracking of that state instead.
--
-- Defaults true only for users who signed up via email/password in the
-- first place (they obviously already have one); false for everyone
-- else (OAuth signups) until they explicitly set one via the app.
-- ============================================================================

alter table public.profiles add column has_password boolean not null default false;

comment on column public.profiles.has_password is 'True once the user has a password set — always true for email/password signups, false for OAuth-only signups until they explicitly add one via My Account.';

-- The default above only gets new rows right via the trigger below, which
-- only fires on INSERT — any row that already existed before this migration
-- ran needs its own backfill to match the same rule (true for email/
-- password signups). Currently a no-op against live data (the only
-- account so far is a Google signup, already correctly false), but a
-- migration that adds a derived column should stay self-consistent
-- regardless of when it's applied, not rely on "there's nobody to fix
-- yet" being true forever.
update public.profiles p
set has_password = true
from auth.users u
where u.id = p.id
  and coalesce(u.raw_app_meta_data ->> 'provider', '') = 'email'
  and p.has_password = false;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, full_name, has_password)
  values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    ),
    coalesce(new.raw_app_meta_data ->> 'provider', '') = 'email'
  );
  return new;
end;
$$;
