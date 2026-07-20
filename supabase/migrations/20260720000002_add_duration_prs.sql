-- ============================================================================
-- Duration PRs for time-tracked exercises
-- ============================================================================
-- all_time_prs.weight is "heaviest weight ever logged" — meaningless for a
-- Plank hold or a Cardio session, where weight is always 0 and the record
-- that actually matters is "longest duration". Rather than a parallel table,
-- this adds one nullable column: weight-based exercises keep using `weight`
-- (reps stays null), time-tracked exercises use `reps` to hold the PR
-- duration in seconds (weight stays 0) — the same reps-field-carries-seconds
-- convention already used by routine_exercises/workout_log_sets for these
-- exercises, so no other schema changes were needed to support them.
-- ============================================================================

alter table public.all_time_prs add column reps smallint;
alter table public.all_time_prs alter column weight set default 0;

comment on column public.all_time_prs.reps is 'PR duration in seconds for time-tracked exercises (trackingType=''time''); null for weight-based exercises.';
