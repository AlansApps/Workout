-- ============================================================================
-- Student self-extend + close a trainer_notes expiry gap
-- ============================================================================
-- Alan's ask: a student should be able to extend their own trainer
-- connection by 30 days with one tap — whether it's already lapsed or just
-- inside the "expiring soon" window — without waiting on the trainer to
-- re-share an invite link. That already worked as a side effect of the
-- trainer re-inviting (claim_trainer_invite's ON CONFLICT), but there was
-- no student-initiated path at all.
--
-- Deliberately excludes status = 'revoked': a lapsed (naturally expired)
-- connection is fair game for the student to self-renew, but a REVOKED one
-- means the trainer explicitly ended the relationship — a student tapping
-- "extend" should never be able to undo that decision. Only a fresh invite
-- from the trainer (claim_trainer_invite) can bring a revoked connection
-- back.
--
-- trainer_connections already has an "Either side of a connection can
-- update it" policy with no column restriction, so a raw client-side
-- .update() from the student would technically work — but it would also
-- let a client touch trainer_id/student_id/connected_at, which is far
-- more than "extend by 30 days" should ever need. This RPC is narrower on
-- purpose: only status/expires_at/renewed_at ever change, only on a row
-- the caller is actually the student of, same shape as claim_trainer_invite.
-- ============================================================================

create or replace function public.extend_own_trainer_connection(p_connection_id uuid)
returns timestamptz
language plpgsql
security definer set search_path = public
as $$
declare
  v_new_expiry timestamptz;
begin
  update public.trainer_connections
  set status = 'active', expires_at = now() + interval '30 days', renewed_at = now()
  where id = p_connection_id and student_id = auth.uid() and status != 'revoked'
  returning expires_at into v_new_expiry;

  if v_new_expiry is null then
    raise exception 'Connection not found or was revoked by your trainer.';
  end if;
  return v_new_expiry;
end;
$$;

comment on function public.extend_own_trainer_connection is 'Student-initiated self-renewal, always resets to 30 days from now — same window claim_trainer_invite() grants when the trainer re-invites. Callable by either an active or an already-lapsed connection''s student.';

-- ── trainer_notes never checked status/expires_at at all — every OTHER
-- trainer-write surface (routines, user_settings, workout logs, PRs,
-- assignments) already requires status='active' and expires_at > now();
-- this table was the one gap, letting a trainer whose connection had fully
-- lapsed keep reading/writing notes on that student indefinitely.
drop policy if exists "Trainer manages their own notes" on public.trainer_notes;

create policy "Trainer manages their own notes"
  on public.trainer_notes for all
  using (
    exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_notes.connection_id and c.trainer_id = auth.uid()
        and c.status = 'active' and c.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.trainer_connections c
      where c.id = trainer_notes.connection_id and c.trainer_id = auth.uid()
        and c.status = 'active' and c.expires_at > now()
    )
  );
