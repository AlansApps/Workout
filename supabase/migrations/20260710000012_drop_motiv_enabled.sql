-- ============================================================================
-- Drop user_settings.motiv_enabled
-- ============================================================================
-- Product decision (2026-07-10): the motivational-quotes/humor feature is
-- being removed from the app entirely, not just left disabled — it was
-- already turned off with no UI to re-enable it, and Alan wants it fully
-- gone rather than left as unused code and an unused column. All
-- references in index.html (the QUIPS/REST_QUIPS/FINISHES/TAGLINES data,
-- the motivEnabled toggle, and every DOM element it touched) were removed
-- in the same batch as this migration.
--
-- No real users exist with a saved preference for this column yet, so
-- there's nothing to migrate or preserve. Verified with a direct row
-- count against the live table immediately before applying this (not
-- just assumed) — the assertion below makes that check part of the
-- migration itself instead of a one-off manual step, so this pattern is
-- self-verifying and safe to reuse for any future destructive migration
-- once real user data exists.
-- ============================================================================

do $$
begin
  if (select count(*) from public.user_settings where motiv_enabled is not null) > 0 then
    raise exception 'Refusing to drop motiv_enabled: % row(s) still have a value',
      (select count(*) from public.user_settings where motiv_enabled is not null);
  end if;
end $$;

alter table public.user_settings drop column motiv_enabled;
