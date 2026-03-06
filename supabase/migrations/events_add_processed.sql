-- Adiciona coluna processed em events (default false).
-- Rodar no SQL Editor do Supabase.

alter table public.events
  add column if not exists processed boolean not null default false;

comment on column public.events.processed is 'Indica se o evento já foi processado (ex.: por n8n/IA).';
