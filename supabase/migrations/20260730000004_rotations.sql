-- ============================================================================
-- Rotations — several named rotations per user, exactly one active
-- ============================================================================
-- Until now a user had one implicit rotation: user_settings.schedule (an
-- ordered array of routine client_ids) plus schedule_pos (which one is NEXT).
-- Alan wants several — a push/pull/legs block, a travel week, an off-season
-- block — with a single active one at a time.
--
-- The critical constraint is that this must not disturb anyone. There are
-- real users mid-programme, and silently resetting which workout is up next
-- would restart their week. So:
--
--   • schedule and schedule_pos are LEFT EXACTLY AS THEY ARE and keep
--     meaning "the active rotation". Nothing that reads them changes — not
--     the other-user profile program view, not an older cached client.
--   • rotations is added ALONGSIDE, carrying the full set.
--   • No backfill runs here. The client wraps an existing schedule into its
--     first rotation on load (migrateRotations), carrying schedule_pos over
--     as that rotation's pos, and pushes the result on its next sync. Doing
--     it client-side rather than in SQL means the identical code path also
--     covers guests, who have no row here at all, and it keeps one
--     implementation of the rule instead of two that must agree.
--
-- Shape of each element:
--   { id: "rot-xxxx", name: "Push Pull Legs", schedule: ["r01","r02"], pos: 0 }
-- name may be "" meaning "not named yet", which the client renders as a
-- translated default so the label follows the app's language until renamed.
-- ============================================================================

alter table public.user_settings
  add column rotations          jsonb not null default '[]'::jsonb,
  add column active_rotation_id text;

comment on column public.user_settings.rotations is 'All of the user''s rotations: [{id,name,schedule[],pos}]. The active one is mirrored into schedule/schedule_pos, which remain the source other readers use.';
comment on column public.user_settings.active_rotation_id is 'Which element of rotations is live. Its schedule/pos are mirrored into schedule/schedule_pos.';

-- No CHECK constraint tying active_rotation_id to a member of rotations.
-- Two reasons. Postgres forbids subqueries in CHECK at all, so it cannot be
-- expressed directly; and more importantly it would be the wrong shape of
-- guarantee here — a violation would make the whole background sync upsert
-- fail, silently stranding a user's data on their device. The client already
-- fails soft instead: activeRotation() falls back to rotations[0] when the id
-- doesn't resolve, and migrateRotations() repairs the id on every load. Self-
-- healing beats rejecting the write on a sync path.


-- ── Assertions: confirm this migration changed no existing scheduling data.
do $$
declare
  rot_default_bad integer;
  sched_col       text;
begin
  -- Every pre-existing row must have taken the empty default, so no user has
  -- been given a rotation they did not create.
  select count(*) into rot_default_bad
    from public.user_settings where rotations <> '[]'::jsonb or active_rotation_id is not null;
  if rot_default_bad <> 0 then
    raise exception 'Expected every existing row to default to no rotations — % did not.', rot_default_bad;
  end if;

  -- schedule/schedule_pos must still be present and untouched: they remain
  -- the active rotation and the thing other readers depend on.
  select string_agg(column_name, ',' order by column_name) into sched_col
    from information_schema.columns
    where table_schema='public' and table_name='user_settings'
      and column_name in ('schedule','schedule_pos');
  if sched_col is distinct from 'schedule,schedule_pos' then
    raise exception 'schedule/schedule_pos must survive this migration, found: %', coalesce(sched_col,'(none)');
  end if;
end $$;
