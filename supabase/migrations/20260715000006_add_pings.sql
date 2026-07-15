-- ============================================================================
-- Pings — a single daily "thinking of you" nudge, not a chat message
-- ============================================================================
-- One row per ping sent. The rate limit ("one ping total per day, to
-- anyone, not one per day per recipient") is enforced by a UNIQUE INDEX on
-- (sender_id, day), not application logic — a unique index is checked
-- atomically by Postgres itself, so two near-simultaneous requests from the
-- same sender (e.g. a double-tap) can't both slip through a race condition
-- the way a "check then insert" RLS policy could. The app just tries the
-- insert and treats a unique-violation (23505) as "already used today".
--
-- message/kind store the picked text verbatim rather than an id referencing
-- a client-side message list — the list can change over time (add/remove/
-- reword entries) without corrupting the meaning of historical pings.
-- ============================================================================

create table public.pings (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  message      text not null,
  kind         text not null check (kind in ('push', 'support')),
  created_at   timestamptz not null default now(),

  check (sender_id <> recipient_id)
);

comment on column public.pings.kind is '"push" renders as "{sender} wants you to {message}"; "support" renders as "{sender} says {message}".';

-- One ping per sender per calendar day, full stop — regardless of who it
-- was sent to. Explicitly pinned to UTC (rather than a plain ::date cast,
-- which depends on the session's timezone setting and Postgres refuses to
-- index for exactly that reason — "functions in index expression must be
-- marked IMMUTABLE") so the day boundary is fixed and this can be a real
-- unique index. Same UTC-day boundary convention already used for
-- session-day-counts elsewhere in this app.
create unique index pings_one_per_sender_per_day on public.pings (sender_id, ((created_at at time zone 'utc')::date));

-- Covers "pings I've received" (the Interactions feed's main query).
create index pings_recipient_id_created_at_idx on public.pings (recipient_id, created_at desc);

alter table public.pings enable row level security;

-- SELECT: either side of a ping can read it — the recipient needs it for
-- their Interactions feed, the sender needs it to check whether they've
-- already used today's ping (no reason to hide either side's own history
-- from them).
create policy "Either party can read a ping"
  on public.pings for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- INSERT: you can only send as yourself. No privacy/visibility check is
-- needed here the way follows has one — a ping doesn't expose or gate any
-- of the recipient's data, it's just a message, so there's nothing to
-- bypass. The daily limit is the unique index above, not this policy.
create policy "Users can send their own pings"
  on public.pings for insert
  with check (auth.uid() = sender_id);

comment on table public.pings is 'One-per-day-per-sender motivational nudge, delivered into the recipient''s Interactions feed. Immutable once sent — no UPDATE/DELETE policies.';
