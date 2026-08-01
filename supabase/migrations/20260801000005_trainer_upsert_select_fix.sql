-- ============================================================================
-- Fix trainer upserts on last_weights / all_time_prs — missing SELECT policy
-- ============================================================================
-- Caught by live RLS testing: `INSERT ... ON CONFLICT (...) DO UPDATE` needs
-- to be able to SEE the row it might be conflicting with, to decide whether
-- the insert or the update branch applies. 20260801000001_trainer_write_
-- access.sql gave the trainer INSERT and UPDATE policies on these two
-- tables, but never a SELECT policy — so the very first upsert against an
-- exercise the student already had a row for (which is any exercise
-- they've ever actually trained) was rejected outright, exactly the
-- workflow Live Session depends on for PR detection.
--
-- Plain INSERT with no existing row worked fine in testing; only the
-- ON CONFLICT DO UPDATE path failed — which is why this wasn't caught by
-- reading the migration alone and needed an actual write against a
-- pre-existing row to surface.
-- ============================================================================

create policy "Trainer can view a last-weight entry for their student"
  on public.last_weights for select
  using (public.is_active_trainer_of(user_id));

create policy "Trainer can view a PR for their student"
  on public.all_time_prs for select
  using (public.is_active_trainer_of(user_id));
