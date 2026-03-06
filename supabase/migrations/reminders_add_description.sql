-- Adiciona coluna description em reminders.
-- Rodar no SQL Editor do Supabase.

alter table public.reminders
  add column if not exists description text;

comment on column public.reminders.description is 'Texto ou descrição do lembrete.';
