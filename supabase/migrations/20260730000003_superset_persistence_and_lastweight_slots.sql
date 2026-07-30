-- ============================================================================
-- Supersets survive the cloud, and duplicate exercises stop overwriting
-- each other's remembered weights
-- ============================================================================
-- Alan's report: build a superset that pairs the SAME exercise twice (a drop
-- set — dumbbell curls at 15kg, then curls at 10kg), and next time the
-- routine is opened the two slots have clobbered one another's weights and
-- reps. Tracing it turned up three separate holes, all of which have to be
-- closed for that routine to round-trip intact.
--
-- 1. last_weights was keyed (user_id, exercise_id). A routine may legitimately
--    list one exercise more than once, and both occurrences read AND wrote
--    that single row — so finishing a workout saved slot A, then immediately
--    overwrote it with slot B, and the next session prefilled both slots from
--    whichever survived. That is exactly the reported symptom. A `slot`
--    column (0 for the first occurrence, 1 for the second, ...) makes the two
--    independent. Note this was never superset-specific: any routine naming
--    the same lift twice had it.
--
-- 2. routine_exercises had no ss_group column, and the client never sent one.
--    Superset grouping is client-only state, so ANY cloud hydrate — new
--    device, re-login, or picking "use my account's data" on the conflict
--    screen — silently flattened every superset into loose exercises.
--
-- 3. routine_exercises stored only one target_sets/target_reps/target_weight
--    triple, but the client keeps per-set rows (`setRows`). A superset whose
--    whole point is 15kg on round one and 10kg on round two cannot be
--    expressed by a single target_weight — the differing weights were dropped
--    on sync even when the grouping happened to be intact.
--
-- Every column added here is nullable or defaulted, and the primary key
-- change is a widening: existing rows all take slot 0, which is the same
-- identity they had before. Nothing is rewritten and nothing is dropped.
-- ============================================================================

-- ── 1. Superset grouping + per-set targets on routine exercises.
-- All nullable: a plain (non-superset) exercise leaves ss_group NULL, and a
-- routine saved by an older client simply has no set_rows, which the client
-- already handles by falling back to target_sets/reps/weight.
alter table public.routine_exercises
  add column ss_group      text,
  add column ss_group_rest smallint,
  add column set_rows      jsonb;

comment on column public.routine_exercises.ss_group is 'Client-generated superset id ("ss-<uid>"). Consecutive rows sharing one value form a superset block. NULL for a standalone exercise.';
comment on column public.routine_exercises.ss_group_rest is 'Rest taken after a full superset round, in seconds. Only meaningful on rows that have an ss_group.';
comment on column public.routine_exercises.set_rows is 'Per-set targets, [{kg,reps},...]. Authoritative when present; target_sets/target_reps/target_weight remain as the flat summary for older clients and for queries.';


-- ── 2. last_weights gains a slot, so one exercise can hold several
-- independent "last time" memories within a routine.
alter table public.last_weights
  add column slot smallint not null default 0 check (slot >= 0);

comment on column public.last_weights.slot is 'Which occurrence of this exercise within a routine. 0 = first (and the value every pre-existing row keeps), 1 = second, etc. Lets a drop-set superset remember 15kg for slot 0 and 10kg for slot 1 instead of one overwriting the other.';

-- Widen the primary key. Doing this as drop+add rather than a new unique
-- index so the table keeps exactly one identifying constraint and the
-- client's upsert can keep targeting the primary key.
alter table public.last_weights drop constraint last_weights_pkey;
alter table public.last_weights add primary key (user_id, exercise_id, slot);


-- ── 3. Assertions. Confirm the widening was purely additive: every row that
-- existed before is still addressable exactly as it was, at slot 0.
do $$
declare
  non_zero integer;
  pk_cols  text;
begin
  select count(*) into non_zero from public.last_weights where slot <> 0;
  if non_zero <> 0 then
    raise exception 'Expected every pre-existing last_weights row to land on slot 0 — % did not.', non_zero;
  end if;

  select string_agg(a.attname, ',' order by k.ord) into pk_cols
    from pg_constraint c
    join lateral unnest(c.conkey) with ordinality as k(attnum, ord) on true
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
   where c.conrelid = 'public.last_weights'::regclass and c.contype = 'p';
  if pk_cols is distinct from 'user_id,exercise_id,slot' then
    raise exception 'last_weights primary key is (%), expected (user_id,exercise_id,slot)', pk_cols;
  end if;
end $$;
