-- ============================================================================
-- Index workout_logs.logged_by_trainer_id
-- ============================================================================
-- Flagged by the db-storage-auditor pass on 20260801000001_trainer_write_access:
-- the new trainer UPDATE policies on workout_logs/workout_log_exercises/
-- workout_log_sets all filter on `logged_by_trainer_id = auth.uid()`.
-- Postgres evaluates every applicable RLS policy with OR semantics, so this
-- filter runs on EVERY write to these tables — including the 99%+ that are
-- an ordinary self-logged session, where logged_by_trainer_id is null and
-- the trainer policy was never going to match. Without an index that filter
-- falls back to a sequential scan on a table that only grows (one row per
-- workout, forever).
--
-- Partial (WHERE logged_by_trainer_id is not null) rather than a full index:
-- almost every row will be null forever (only trainer-logged sessions ever
-- set it), so a full btree would mostly index a column that is not-null in
-- a small minority of rows for no benefit.
-- ============================================================================

create index workout_logs_logged_by_trainer_id_idx
  on public.workout_logs (logged_by_trainer_id)
  where logged_by_trainer_id is not null;
