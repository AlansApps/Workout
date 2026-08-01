-- ============================================================================
-- Fix guard_trainer_user_settings_update() — referenced a dropped column
-- ============================================================================
-- 20260801000001_trainer_write_access.sql copied its protected-column list
-- from the ORIGINAL user_settings migration (20260710000005) without
-- checking for later schema changes. Two problems, both caught by live
-- RLS testing against production before this ever reached real users:
--
-- 1. motiv_enabled was dropped in 20260710000012_drop_motiv_enabled.sql —
--    referencing it in the trigger raised a hard Postgres error
--    ("record new has no field motiv_enabled") on every trainer-initiated
--    update, rather than the intended silent guard.
-- 2. weight_prefs (added later, in 20260724000001_weight_logging_prefs.sql)
--    was never added to the protected list at all — a trainer update
--    could have silently overwritten a student's own bodyweight/barbell/
--    unit preferences, which is exactly the kind of non-rotation field
--    this guard exists to protect.
--
-- No client code depends on the exact current column list here — this is
-- a straight CREATE OR REPLACE of the function body, same trigger.
-- ============================================================================

create or replace function public.guard_trainer_user_settings_update()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() <> new.user_id then
    if new.theme is distinct from old.theme
      or new.accent is distinct from old.accent
      or new.lang is distinct from old.lang
      or new.last_notes is distinct from old.last_notes
      or new.weight_prefs is distinct from old.weight_prefs
    then
      raise exception 'Trainers can only edit a student''s rotation and schedule fields.';
    end if;
  end if;
  return new;
end;
$$;
