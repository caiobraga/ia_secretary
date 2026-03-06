-- =============================================================================
-- Permite INSERT em events sem autenticação (ex.: n8n com chave anon).
-- Rode no SQL Editor do Supabase.
--
-- Remove a policy "for all" e cria duas: uma para SELECT/UPDATE/DELETE (só dono)
-- e outra para INSERT (dono OU anon). Assim o n8n consegue inserir sem JWT.
--
-- Atenção: qualquer cliente com a chave anon pode inserir eventos com qualquer
-- user_id. Use só se a chave anon não for exposta ou se o n8n for o único
-- cliente que insere sem login.
-- =============================================================================

-- 1) Remove a policy atual que exige auth em tudo
drop policy if exists "Users can manage their events" on public.events;
drop policy if exists "Allow anon insert into events" on public.events;

-- 2) SELECT / UPDATE / DELETE: só o dono do evento
create policy "Events select update delete own"
on public.events
for select
using (auth.uid() = user_id);

create policy "Events update delete own"
on public.events
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Events delete own"
on public.events
for delete
using (auth.uid() = user_id);

-- 3) INSERT: usuário autenticado (só nos seus) OU sem autenticação (anon/n8n)
create policy "Events insert own or anon"
on public.events
for insert
with check (auth.uid() = user_id or auth.uid() is null);

-- =============================================================================
-- No n8n: use INSERT direto na tabela events (Supabase node).
-- Envie no body: user_id, title, start_time, end_time, etc.
-- =============================================================================
