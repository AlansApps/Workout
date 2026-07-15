-- ============================================================================
-- Add profiles.is_private — Instagram-style private account toggle
-- ============================================================================
-- Powers a "Private Account" toggle in Settings. This column is added now
-- (ahead of the actual public-profile-viewing feature) so the preference
-- is durable and server-side from day one — it has to live in the
-- database rather than local device storage, since OTHER users' clients
-- will eventually need to read it to decide whether to show a locked
-- placeholder instead of the profile's Program/Log content.
--
-- The actual enforcement (hiding Program/Log from non-followers when
-- true) is not wired up yet — that ships together with the
-- public-profile-viewing feature. Until then this column is inert:
-- everyone still only ever sees their own profile.
--
-- Defaults to false (public), matching how every existing account has
-- behaved so far — flipping this on is an explicit opt-in action a user
-- takes in Settings, never a silent default change to their visibility.
-- ============================================================================

alter table public.profiles add column is_private boolean not null default false;

comment on column public.profiles.is_private is 'True if the user has enabled "Private Account" in Settings. Enforcement (hiding Program/Log from non-followers) is implemented alongside the public-profile-viewing feature, not by this migration alone.';
