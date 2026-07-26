-- ============================================================================
-- Trainer feature MVP: connections, invite links, assignments
-- ============================================================================
-- Scope is deliberately the roster + connect + assign/view flow only —
-- progressive-overload nudges are a separate future pass (Alan's own call:
-- get this core loop solid first).
--
-- A trainer-student connection is a real, persistent relationship (unlike
-- routine-sharing, which is a stateless URL-encoded blob with no server
-- state at all) — both sides need to see it from any device, and it has to
-- expire/renew/revoke, so it needs its own table and RLS.
-- ============================================================================

-- ── Invite links: one-time use, same mental model as routine-sharing —
-- a trainer generates a fresh link per student and sends it once. A
-- persistent reusable link was the original design, but Alan's own call
-- was that a leaked reusable link could connect the wrong person to a
-- trainer indefinitely; a one-off link is dead the moment it's claimed
-- (or never claimed at all), so a leak after use is harmless. Renewing an
-- existing student just means sending them a fresh invite — the
-- ON CONFLICT upsert in claim_trainer_invite() below still recognizes the
-- same trainer/student pair and extends their existing connection rather
-- than creating a duplicate.
create table public.trainer_invites (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  -- gen_random_uuid() (not gen_random_bytes(), which needs the pgcrypto
  -- extension enabled and isn't guaranteed available) is already relied on
  -- elsewhere in this same file for primary keys — reusing it here avoids
  -- a new extension dependency for what's just a random-enough token.
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now(),
  used_by uuid references public.profiles(id),
  used_at timestamptz
);

create index trainer_invites_trainer_idx on public.trainer_invites(trainer_id);

alter table public.trainer_invites enable row level security;

-- A student claiming a link never needs to SELECT this table directly —
-- claim_trainer_invite() below does the lookup itself as security
-- definer. Only the trainer ever needs to see their own invite rows.
create policy "Trainer can view their own invites"
  on public.trainer_invites for select
  using (auth.uid() = trainer_id);

create policy "Trainer can create their own invites"
  on public.trainer_invites for insert
  with check (auth.uid() = trainer_id);

-- ── The relationship itself.
create table public.trainer_connections (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.profiles(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active','revoked')),
  connected_at timestamptz not null default now(),
  renewed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '30 days'),
  constraint trainer_connections_not_self check (trainer_id <> student_id),
  unique (trainer_id, student_id)
);

create index trainer_connections_trainer_idx on public.trainer_connections(trainer_id);
create index trainer_connections_student_idx on public.trainer_connections(student_id);

alter table public.trainer_connections enable row level security;

-- Both sides of a connection need to see it — the trainer for their
-- roster, the student to know who they're connected to and until when.
create policy "Either side of a connection can view it"
  on public.trainer_connections for select
  using (auth.uid() = trainer_id or auth.uid() = student_id);

-- Connections are only ever created via claim_trainer_invite() below
-- (security definer, runs as the trainer) — a plain client-side insert
-- would need the STUDENT's session to satisfy "auth.uid() = trainer_id",
-- which it never can, so this policy is effectively RPC-only in practice.
create policy "Only the trainer side can create a connection"
  on public.trainer_connections for insert
  with check (auth.uid() = trainer_id);

-- Either side can change status — the student revoking access, or the
-- trainer renewing/revoking their end.
create policy "Either side of a connection can update it"
  on public.trainer_connections for update
  using (auth.uid() = trainer_id or auth.uid() = student_id);

-- ── Claiming an invite: the student only has the token, not the trainer's
-- id, so this has to run as security definer to satisfy the insert policy
-- above under the trainer's identity rather than the calling student's.
-- `select ... for update` locks the invite row for the rest of this
-- transaction, so two people opening the same link at the same instant
-- can't both succeed — the second waits for the first to commit, then
-- correctly sees used_by already set and gets rejected.
-- Renewing an existing student means sending them a NEW invite (each one
-- is single-use) — the ON CONFLICT here still just extends their existing
-- connection rather than creating a duplicate row.
create or replace function public.claim_trainer_invite(invite_token text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_invite public.trainer_invites;
  v_connection_id uuid;
begin
  select * into v_invite from public.trainer_invites where token = invite_token for update;
  if v_invite.id is null then
    raise exception 'This invite link is not valid.';
  end if;
  if v_invite.used_by is not null then
    raise exception 'This invite link has already been used.';
  end if;
  if v_invite.trainer_id = auth.uid() then
    raise exception 'You cannot connect to your own invite link.';
  end if;

  update public.trainer_invites set used_by = auth.uid(), used_at = now() where id = v_invite.id;

  insert into public.trainer_connections (trainer_id, student_id, status, expires_at, renewed_at)
  values (v_invite.trainer_id, auth.uid(), 'active', now() + interval '30 days', now())
  on conflict (trainer_id, student_id)
  do update set status='active', expires_at=now() + interval '30 days', renewed_at=now()
  returning id into v_connection_id;

  return v_connection_id;
end;
$$;

-- ── Assigned routines: a snapshot of exercises/sets/reps/target weight at
-- assignment time, not a live reference to the trainer's own routine (which
-- could change or be deleted later) — same "snapshot, not pointer" choice
-- routine-sharing already makes, for the same reason.
create table public.trainer_assignments (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.trainer_connections(id) on delete cascade,
  routine_name text not null,
  exercises jsonb not null,
  assigned_at timestamptz not null default now()
);

create index trainer_assignments_connection_idx on public.trainer_assignments(connection_id);

alter table public.trainer_assignments enable row level security;

-- Asymmetric on purpose: the student keeps seeing what was assigned to
-- them even after the connection lapses (it's their own routine now, not
-- something that should vanish because 30 days passed) — but the trainer
-- only sees it while the connection is active/non-expired, matching the
-- access they have to everything else about that student. Without this
-- check a revoked or expired trainer would keep read access to past
-- assignments even though can_view_profile_content() already cut off
-- their access to the student's current logs/routines.
create policy "Student always sees their assignments; trainer only while active"
  on public.trainer_assignments for select
  using (
    exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_assignments.connection_id
        and (
          c.student_id = auth.uid()
          or (c.trainer_id = auth.uid() and c.status = 'active' and c.expires_at > now())
        )
    )
  );

create policy "Only the trainer half of the connection can assign"
  on public.trainer_assignments for insert
  with check (
    exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_assignments.connection_id
        and c.trainer_id = auth.uid()
    )
  );

-- ── Widen the existing visibility check rather than duplicating six new
-- policies: can_view_profile_content() already gates every one of
-- routines/routine_exercises/user_settings/workout_logs/
-- workout_log_exercises/workout_log_sets (see
-- 20260715000003_public_profile_visibility.sql). Adding "or an active
-- trainer connection" here means a trainer sees a connected student's
-- current program too, not just raw session history — which is the point
-- of the feature (assign/track progress), not just Log-tab access. Purely
-- additive: only ever WIDENS who can view, never narrows the existing
-- public/follow checks.
create or replace function public.can_view_profile_content(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = target_user_id
      and (
        p.is_private = false
        or exists (
          select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.following_id = target_user_id
            and f.status = 'accepted'
        )
        or exists (
          select 1 from public.trainer_connections tc
          where tc.trainer_id = auth.uid()
            and tc.student_id = target_user_id
            and tc.status = 'active'
            and tc.expires_at > now()
        )
      )
  );
$$;
