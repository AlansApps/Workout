-- ============================================================================
-- Per-user settings and routine schedule
-- ============================================================================
-- One row per user. Bundles display preferences (theme/accent/language) with
-- the routine rotation (schedule + schedule_pos), since both are simple,
-- rarely-queried, whole-row reads: the app loads them once per session and
-- writes them back as a unit, never filtering or aggregating across users.
--
-- `schedule` is a JSONB array of routine ids (e.g. ["r01", "r03", "r05"])
-- rather than a separate join table — it's a short, ordered, user-editable
-- list that's never queried in isolation, so a relational table would only
-- add write overhead without any read benefit.
--
-- `last_notes` mirrors the client's transient "last note typed for this
-- routine" draft cache (keyed by routine id, cleared once a workout using
-- that routine is finished) — same JSONB reasoning as schedule: small,
-- whole-row, never filtered.
-- ============================================================================

create table public.user_settings (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  theme          text not null default 'dark' check (theme in ('dark', 'light')),
  accent         text not null default 'Gold' check (char_length(accent) <= 30),
  motiv_enabled  boolean not null default true,
  lang           text not null default 'en' check (char_length(lang) <= 10),
  schedule       jsonb not null default '[]'::jsonb,
  schedule_pos   smallint not null default 0,
  last_notes     jsonb not null default '{}'::jsonb,
  updated_at     timestamptz not null default now()
);

create trigger user_settings_set_updated_at
  before update on public.user_settings
  for each row
  execute function public.set_updated_at();

-- ── Row Level Security ──
alter table public.user_settings enable row level security;

create policy "Users can manage their own settings"
  on public.user_settings for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
