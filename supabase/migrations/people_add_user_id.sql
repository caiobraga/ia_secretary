-- Adiciona user_id em people e ajusta RLS (para tabela já existente).
-- Rodar no SQL Editor do Supabase.
-- Se existirem linhas sem created_by, preencha antes: update people set user_id = 'uuid' where user_id is null;
-- ou delete from people where created_by is null and user_id is null;

-- 1) Adicionar coluna user_id (nullable primeiro)
alter table public.people
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

-- 2) Preencher a partir de created_by, se existir
update public.people p
set user_id = p.created_by
where p.created_by is not null and p.user_id is null;

-- 3) Tornar user_id obrigatório (falha se existir linha com user_id null)
alter table public.people
  alter column user_id set not null;

-- 4) Remover created_by se existir (opcional; descomente se quiser)
-- alter table public.people drop column if exists created_by;

-- 5) Índice
create index if not exists idx_people_user_id on public.people(user_id);

-- 6) RLS: remover policies antigas e criar novas
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
