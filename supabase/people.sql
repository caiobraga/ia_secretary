-- =============================================================================
-- People table: contatos/pessoas por usuário (user_id). Inserção anon permitida (ex.: n8n).
-- Rodar no SQL Editor do Supabase (após schema_full.sql ou standalone).
-- =============================================================================

-- Ensure updated_at helper exists (skip if you already ran schema_full.sql)
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- 1. People table (com user_id = dono do contato)
create table if not exists public.people (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  email text,
  phone text,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.people enable row level security;

create trigger trg_people_updated_at
  before update on public.people
  for each row
  execute procedure public.handle_updated_at();

-- 2. Indexes
create index if not exists idx_people_user_id on public.people(user_id);
create index if not exists idx_people_email on public.people(email);
create index if not exists idx_people_created_at on public.people(created_at desc);

-- 3. RLS: cada usuário vê/edita só seus contatos; INSERT permite anon (n8n) ou dono
drop policy if exists "Anyone can insert people" on public.people;
drop policy if exists "Anyone can select people" on public.people;
drop policy if exists "Authenticated can update people" on public.people;
drop policy if exists "Authenticated can delete people" on public.people;

create policy "People select own"
  on public.people for select
  using (auth.uid() = user_id);

create policy "People insert own or anon"
  on public.people for insert
  with check (auth.uid() = user_id or auth.uid() is null);

create policy "People update own"
  on public.people for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "People delete own"
  on public.people for delete
  using (auth.uid() = user_id);
