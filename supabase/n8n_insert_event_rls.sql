-- =============================================================================
-- Inserir em events pelo n8n (anon key) sem mudar a policy RLS da tabela.
-- Rode no SQL Editor do Supabase.
--
-- O n8n chama a função via RPC em vez de INSERT direto na tabela.
-- A função roda com privilégios do dono (SECURITY DEFINER) e contorna o RLS.
-- =============================================================================

create or replace function public.insert_event(
  p_user_id uuid,
  p_title text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_description text default null,
  p_location text default null,
  p_all_day boolean default false,
  p_status text default 'scheduled'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.events (
    user_id, title, description, location,
    start_time, end_time, all_day, status
  )
  values (
    p_user_id, p_title, p_description, p_location,
    p_start_time, p_end_time, p_all_day, p_status
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Permite o n8n (anon) e o app (authenticated) chamarem a função
grant execute on function public.insert_event(uuid, text, timestamptz, timestamptz, text, text, boolean, text)
  to anon, authenticated;

comment on function public.insert_event is 'Inserção em events para n8n/backend; contorna RLS com SECURITY DEFINER.';

-- =============================================================================
-- No n8n: use o node "Supabase" e chame "Execute Query" / RPC:
--   Method: POST
--   Table/RPC: rpc/insert_event
--   Body (JSON):
--   {
--     "p_user_id": "uuid-do-usuario",
--     "p_title": "Título",
--     "p_start_time": "2025-02-15T14:00:00Z",
--     "p_end_time": "2025-02-15T15:00:00Z",
--     "p_description": "opcional",
--     "p_location": "opcional",
--     "p_all_day": false,
--     "p_status": "scheduled"
--   }
-- Ou no Postgres node: select insert_event('uuid', 'Título', '...'::timestamptz, '...'::timestamptz);
-- =============================================================================
