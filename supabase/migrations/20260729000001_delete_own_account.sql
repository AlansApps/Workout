-- ============================================================================
-- Self-service account deletion
-- ============================================================================
-- Required by BOTH stores before we can submit:
--   • Apple App Store Review Guideline 5.1.1(v) — in-app account deletion,
--     mandatory since June 2022. Deactivating is explicitly not enough; the
--     account and its personal data have to actually go.
--   • Google Play User Data policy — same requirement, enforced since
--     April 2024, plus a public web URL for people who no longer have the
--     app installed (that part is hosting work, not schema — tracked
--     separately).
--
-- Deleting the auth.users row is all that's needed: every table that holds
-- user data hangs off auth.users (or off profiles, which itself cascades
-- from auth.users) with ON DELETE CASCADE, so one delete unwinds the whole
-- graph — profiles, routines, workout_logs and their exercises/sets,
-- last_weights, all_time_prs, user_settings, user_exercise_notes, follows
-- (both directions), pings (both directions), user_insignias,
-- trainer_invites, trainer_connections, and trainer_assignments (which
-- cascades from trainer_connections).
--
-- ...with exactly one exception, fixed below.
-- ============================================================================

-- ── The one FK that would have blocked deletion outright.
-- trainer_invites.used_by was declared as a bare `references
-- public.profiles(id)` with no ON DELETE clause, which means NO ACTION.
-- So any user who had ever CLAIMED a trainer invite could never be
-- deleted — Postgres would raise a foreign-key violation and abort the
-- whole transaction. Nobody would have hit this until the first student
-- tried to delete their account, at which point deletion would be broken
-- for exactly the users hardest to debug remotely.
--
-- SET NULL rather than CASCADE on purpose: the invite row is the trainer's
-- own record of a link they issued, and it shouldn't silently vanish from
-- their history because the student left. Nulling used_by keeps the row
-- (and its used_at timestamp) while dropping the reference to a person
-- who no longer exists.
--
-- Not guarded by an assertion the way the DROP COLUMN migrations are:
-- this only changes what happens on FUTURE deletes and cannot lose any
-- data that exists today.
alter table public.trainer_invites
  drop constraint if exists trainer_invites_used_by_fkey;

alter table public.trainer_invites
  add constraint trainer_invites_used_by_fkey
  foreign key (used_by) references public.profiles(id) on delete set null;


-- ── The deletion entry point.
-- security definer because auth.users is not writable by the authenticated
-- role — only the function owner can remove that row. The function is
-- deliberately tiny and takes no arguments: it can ONLY ever delete the
-- caller's own account, because the id comes from auth.uid() inside the
-- function rather than from anything the client sends. There is no
-- parameter an attacker could point at somebody else's row.
--
-- search_path is pinned (the standard hardening for security definer
-- functions) so a caller can't shadow `auth` or `public` with their own
-- schema and trick the function into resolving those names somewhere else.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- One delete; the ON DELETE CASCADE graph described in the header does
  -- the rest. Kept as a single statement so it's atomic — a partial
  -- delete that left orphaned workout history behind would be worse than
  -- a clean failure the user can retry.
  delete from auth.users where id = uid;
end;
$$;

-- Only a signed-in user can call this. anon has no account to delete, and
-- leaving EXECUTE on public would expose it to the anon role too.
revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;
