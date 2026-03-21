-- =============================================================================
-- Schema completo do banco (contexto para o projeto IA Secretary)
-- Rodar no SQL Editor do Supabase na ordem abaixo.
-- =============================================================================

-- 1. Extensions (rodar primeiro)
create extension if not exists "pgcrypto";

-- 2. Função para auto update de updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- 3. Calendars
create table public.calendars (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  description text,
  color text default '#3B82F6',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.calendars enable row level security;

create trigger trg_calendars_updated_at
before update on public.calendars
for each row
execute procedure public.handle_updated_at();

-- 4. Events (Agenda) — scoped by user_id only (no calendar_id)
create table public.events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  title text not null,
  description text,
  location text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  all_day boolean default false,
  status text default 'scheduled',
  processed boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.events enable row level security;

create trigger trg_events_updated_at
before update on public.events
for each row
execute procedure public.handle_updated_at();

-- 5. Event Participants
create table public.event_participants (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.events(id) on delete cascade,
  email text not null,
  name text,
  role text default 'attendee',
  response_status text default 'pending'
);

alter table public.event_participants enable row level security;

-- 6. Reminders
create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.events(id) on delete cascade,
  remind_at timestamptz not null,
  method text default 'notification',
  description text,
  relembrado boolean not null default false
);

alter table public.reminders enable row level security;

-- 7. Meeting Notes
create table public.meeting_notes (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.events(id) on delete cascade,
  title text,
  content text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.meeting_notes enable row level security;

create trigger trg_notes_updated_at
before update on public.meeting_notes
for each row
execute procedure public.handle_updated_at();

-- 8. Action Items
create table public.action_items (
  id uuid primary key default gen_random_uuid(),
  meeting_note_id uuid references public.meeting_notes(id) on delete cascade,
  description text not null,
  assigned_to uuid references auth.users(id),
  due_date timestamptz,
  status text default 'open',
  created_at timestamptz default now()
);

alter table public.action_items enable row level security;

-- 9. Índices
create index idx_events_user_id on public.events(user_id);
create index idx_events_start_time on public.events(start_time);
create index idx_notes_event_id on public.meeting_notes(event_id);
create index idx_reminders_event_id on public.reminders(event_id);

-- 10. RLS Policies (ESSENCIAL)

-- Calendars
create policy "Users can manage their calendars"
on public.calendars
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Events
create policy "Users can manage their events"
on public.events
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Participants
create policy "Users can manage participants"
on public.event_participants
for all
using (
  exists (select 1 from public.events e where e.id = event_participants.event_id and e.user_id = auth.uid())
)
with check (
  exists (select 1 from public.events e where e.id = event_participants.event_id and e.user_id = auth.uid())
);

-- Reminders
create policy "Users can manage reminders"
on public.reminders
for all
using (
  exists (select 1 from public.events e where e.id = reminders.event_id and e.user_id = auth.uid())
)
with check (
  exists (select 1 from public.events e where e.id = reminders.event_id and e.user_id = auth.uid())
);

-- Meeting Notes
create policy "Users can manage notes"
on public.meeting_notes
for all
using (
  exists (select 1 from public.events e where e.id = meeting_notes.event_id and e.user_id = auth.uid())
)
with check (
  exists (select 1 from public.events e where e.id = meeting_notes.event_id and e.user_id = auth.uid())
);

-- Action Items
create policy "Users can manage action items"
on public.action_items
for all
using (
  exists (
    select 1 from public.meeting_notes mn
    join public.events e on e.id = mn.event_id
    where mn.id = action_items.meeting_note_id and e.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.meeting_notes mn
    join public.events e on e.id = mn.event_id
    where mn.id = action_items.meeting_note_id and e.user_id = auth.uid()
  )
);
