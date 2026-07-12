-- ============================================================================
-- Username rules: Instagram-style format + reserved-term blocking
-- ============================================================================
-- Tightens the username format to match Instagram's actual rules — no
-- leading/trailing/consecutive periods — on top of the existing
-- lowercase-letters/digits/dot/underscore/3-30-char constraint already on
-- profiles.username (see 20260710000001_profiles.sql). Also adds a
-- reserved-terms table so a username can't impersonate the app or claim a
-- generic support-style handle.
--
-- This only seeds impersonation-prone RESERVED words (admin, support, the
-- app's own brand names, etc.) — it deliberately does NOT ship a slur or
-- profanity list. Building a good one (multi-language, low false-positive
-- rate) is a real content-moderation task on its own, better sourced from
-- an established, actively-maintained list than hand-written here. The
-- table and function below are the extension point for that whenever
-- Alan wants to populate it — just INSERT more terms into
-- reserved_usernames, no code or migration changes needed. Client-side
-- validation should call the same is_username_allowed() function (see
-- validateUsername() in index.html) so both sides always agree.
-- ============================================================================

create table public.reserved_usernames (
  term text primary key
);

comment on table public.reserved_usernames is 'Usernames blocked as a substring match: impersonation-prone reserved words today, extensible later with an offensive-terms list — see migration header.';

insert into public.reserved_usernames (term) values
  ('admin'),('administrator'),('root'),('support'),('help'),
  ('moderator'),('mod'),('official'),('staff'),('team'),
  ('alansworkout'),('alansapps');

create function public.is_username_allowed(candidate text)
returns boolean
language sql
stable
as $$
  select not exists (
    select 1 from public.reserved_usernames
    where candidate ilike '%' || term || '%'
  );
$$;

comment on function public.is_username_allowed is 'True if the username does not contain any reserved/banned term as a substring. Single source of truth for both the profiles CHECK constraint below and client-side pre-validation.';

alter table public.profiles
  add constraint profiles_username_no_edge_dots
  check (username !~ '^\.' and username !~ '\.$');

alter table public.profiles
  add constraint profiles_username_no_double_dots
  check (username !~ '\.\.');

alter table public.profiles
  add constraint profiles_username_allowed
  check (username is null or public.is_username_allowed(username));

-- ── Row Level Security ──
-- Read-only for everyone signed in — the app needs to check candidate
-- usernames against this list before submitting a signup. Only writable
-- via migrations / the dashboard, never through the app's own API surface.
alter table public.reserved_usernames enable row level security;

create policy "Authenticated users can read reserved usernames"
  on public.reserved_usernames for select
  to authenticated
  using (true);
