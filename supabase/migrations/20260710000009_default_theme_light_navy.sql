-- ============================================================================
-- Change default theme/accent to light mode + Navy
-- ============================================================================
-- Product decision (2026-07-10): new accounts should start on light mode
-- with the Navy accent, instead of the original dark/Gold defaults. This
-- only changes the DEFAULT applied when a user_settings row is created
-- without explicit values — it does not touch any existing row, so nobody
-- who already chose their own theme/accent is affected.
--
-- The client mirrors this same default for brand-new local installs (see
-- loadSettings() in index.html) so a fresh phone and a fresh account both
-- start from the same place.
-- ============================================================================

alter table public.user_settings alter column theme set default 'light';
alter table public.user_settings alter column accent set default 'Navy';
