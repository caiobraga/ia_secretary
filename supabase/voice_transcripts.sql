-- Run this in Supabase SQL Editor to store voice transcripts from the IA Secretary app.
-- Table: voice_transcripts (used by the app; RLS uses auth.uid() so enable Anonymous sign-in if you use it).

create table if not exists public.voice_transcripts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  text text not null,
  is_final boolean default true,
  created_at timestamptz default now()
);

alter table public.voice_transcripts enable row level security;

create index if not exists idx_voice_transcripts_user_id on public.voice_transcripts(user_id);
create index if not exists idx_voice_transcripts_created_at on public.voice_transcripts(created_at);

-- Users can only see and insert their own transcripts
create policy "Users can manage their voice transcripts"
on public.voice_transcripts
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Optional: enable Anonymous sign-ins in Supabase Dashboard → Authentication → Providers → Anonymous
-- so the app can sign in without a login screen and still have a user_id for RLS.
