-- ============================================================================
-- Trainer notes — internal (trainer-only) and external (student-visible)
-- ============================================================================
-- Alan's spec split one idea into two tools: a general, trainer-only running
-- log per student (injury flags, reminders — never tied to a routine), and
-- a student-visible cue that can optionally be attached to a specific
-- rotation or the next time they open a specific routine.
--
-- scope_ref is a plain text id rather than a foreign key on purpose:
-- rotations live inside user_settings.rotations (a JSONB array, no table of
-- its own — see 20260730000004_rotations.sql), so there is no rotations
-- table row to reference. Storing the client-side rotation id ("rot-xxxx")
-- or routine client_id ("r01") and matching it client-side is the same
-- "stable client-assigned id" pattern client_id already uses on routines
-- and workout_logs for exactly this reason.
-- ============================================================================

create table public.trainer_notes (
  id            uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.trainer_connections (id) on delete cascade,
  visibility    text not null check (visibility in ('internal', 'external')),
  scope         text not null default 'general' check (scope in ('general', 'rotation', 'workout')),
  scope_ref     text check (char_length(scope_ref) <= 50),
  body          text not null check (char_length(body) <= 2000),
  created_at    timestamptz not null default now(),

  constraint trainer_notes_scope_ref_shape check (
    (scope = 'general' and scope_ref is null) or
    (scope <> 'general' and scope_ref is not null)
  )
);

comment on column public.trainer_notes.scope is 'general = not tied to anything, exactly the internal-notes case Alan asked for. rotation/workout let an external note surface at the right moment instead of buried in a flat feed.';
comment on column public.trainer_notes.scope_ref is 'The rotation''s or routine''s client-assigned id (rot-xxxx / r01), matched client-side — see the file header for why this cannot be a foreign key.';

-- Covers "this connection's notes, newest first" — the only read pattern
-- either side needs.
create index trainer_notes_connection_id_created_at_idx on public.trainer_notes (connection_id, created_at desc);

alter table public.trainer_notes enable row level security;

-- Trainer-owned data: full create/edit/delete on their own notes, same as
-- any other purely-theirs table in this app (pings, PR events aside — this
-- one has no immutability requirement, a trainer can retract or fix a note
-- they wrote).
create policy "Trainer manages their own notes"
  on public.trainer_notes for all
  using (
    exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_notes.connection_id and c.trainer_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_notes.connection_id and c.trainer_id = auth.uid()
    )
  );

-- Student: read-only, external notes addressed to them only. No INSERT/
-- UPDATE/DELETE policy for the student at all — this is the trainer's tool,
-- not a two-way thread.
create policy "Student can read external notes addressed to them"
  on public.trainer_notes for select
  using (
    visibility = 'external'
    and exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_notes.connection_id and c.student_id = auth.uid()
    )
  );
