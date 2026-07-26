-- ============================================================================
-- Account-scoped onboarding tips
-- ============================================================================
-- The onboarding tip system (index.html — hasSeenTip()/markTipSeen()) fires
-- each contextual tip once per ACCOUNT, not once per device: opening the app
-- on a new phone shouldn't re-show tips already dismissed elsewhere. That
-- requires the "seen" flags to live on the profile itself, not localStorage.
--
-- One exception stays purely local: the very first app-open tip (theme +
-- accent picker) fires before any account necessarily exists — guests get
-- it too — so it's keyed in localStorage only and never touches this column.
--
-- Shape: a flat map of tipId -> true, e.g. {"settings":true,"program":true}.
-- Unconditionally additive (new column, default applies to existing rows,
-- nothing dropped or renamed) — safe independent of the on-hold membership
-- tiers migration.
-- ============================================================================

alter table public.profiles
  add column onboarding_seen jsonb not null default '{}'::jsonb;
