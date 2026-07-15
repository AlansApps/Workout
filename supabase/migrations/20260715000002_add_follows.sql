-- ============================================================================
-- Follows
-- ============================================================================
-- One row per follow relationship (or pending request). A single table
-- drives both "who follows me" and "who's requested to follow me" — they're
-- just different filters on the same status column, not separate concepts.
--
-- status='pending' means the follower is waiting on the target's approval
-- (only happens when the target's profile is private — see the insert
-- policy below). status='accepted' is an active follow, whether it started
-- pending-then-approved or was auto-accepted because the target was public
-- at the time.
-- ============================================================================

create table public.follows (
  follower_id   uuid not null references auth.users (id) on delete cascade,
  following_id  uuid not null references auth.users (id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at    timestamptz not null default now(),
  accepted_at   timestamptz,

  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

comment on column public.follows.accepted_at is 'Set when status flips to accepted — either immediately (public target, auto-accept) or later when the target confirms a pending request. Drives "X is now following you" ordering, separate from created_at which is when the request/follow was first made.';

-- Covers "who follows user X" (profile follower counts, "is now following
-- you" feed, pending-requests list) and "who does user X follow" (following
-- counts, "already following" checks) — the two directions the app queries.
create index follows_following_id_status_idx on public.follows (following_id, status);
create index follows_follower_id_status_idx on public.follows (follower_id, status);

-- Sets accepted_at server-side whenever a row becomes accepted (auto-accept
-- on insert for a public target, or the target's later approval of a
-- pending request) — never trusts a client-supplied timestamp for this.
create function public.set_follow_accepted_at()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'accepted' and (old is null or old.status is distinct from 'accepted') then
    new.accepted_at = now();
  end if;
  return new;
end;
$$;

create trigger follows_set_accepted_at
  before insert or update on public.follows
  for each row
  execute function public.set_follow_accepted_at();

alter table public.follows enable row level security;

-- SELECT: an accepted follow is public information (same as Instagram's
-- follower/following counts and lists being visible to anyone). A pending
-- request is only visible to the two people it actually concerns — nobody
-- else should be able to see who's requested to follow whom.
create policy "Accepted follows are publicly readable, pending only to the two parties"
  on public.follows for select
  using (
    status = 'accepted'
    or auth.uid() = follower_id
    or auth.uid() = following_id
  );

-- INSERT: you can only create a follow FROM yourself — but critically, you
-- can only insert it as already 'accepted' if the target's profile is
-- actually public. Without this check a client could set status='accepted'
-- directly on the insert and silently bypass a private account's approval
-- entirely; 'pending' is always allowed as the safe default regardless of
-- the target's privacy setting.
create policy "Users can create their own follow requests"
  on public.follows for insert
  with check (
    auth.uid() = follower_id
    and (
      status = 'pending'
      or (
        status = 'accepted'
        and exists (
          select 1 from public.profiles
          where profiles.id = following_id and profiles.is_private = false
        )
      )
    )
  );

-- UPDATE: only the target of a pending request can accept it (flip
-- pending -> accepted). No other transition is allowed via update — e.g. a
-- follower can't use update to retroactively mark their own request
-- accepted; they'd need the target's action for that.
create policy "Target user can accept a pending follow request"
  on public.follows for update
  using (auth.uid() = following_id and status = 'pending')
  with check (auth.uid() = following_id and status = 'accepted');

-- DELETE: the follower can cancel their own pending request or unfollow;
-- the target can reject a pending request or remove an existing follower.
create policy "Either party can remove a follow relationship"
  on public.follows for delete
  using (auth.uid() = follower_id or auth.uid() = following_id);
