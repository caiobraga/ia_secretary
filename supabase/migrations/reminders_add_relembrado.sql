-- Lembrete já foi entregue (notificação/voz) ou não aplica mais.
-- false = ainda deve disparar no remind_at (válido para relembrar).
-- true = já relembrado; para lembrar de novo: UPDATE ... SET relembrado = false WHERE id = '...';

alter table public.reminders
  add column if not exists relembrado boolean not null default false;

comment on column public.reminders.relembrado is
  'false = pendente de aviso no horário remind_at; true = já notificado pelo app. Reativar: UPDATE SET relembrado = false.';

create index if not exists idx_reminders_relembrado_pending_at
  on public.reminders (remind_at)
  where relembrado = false;

-- Lembretes muito antigos ainda com false não seriam pegos pela janela do app; marcamos como tratados.
update public.reminders
set relembrado = true
where relembrado = false
  and remind_at < (now() - interval '2 days');
