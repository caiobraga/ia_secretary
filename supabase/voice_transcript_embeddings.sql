-- =============================================================================
-- Vector store para voice transcripts: permite perguntas à IA (RAG / busca semântica).
-- Rodar no SQL Editor do Supabase. Habilitar extensão "vector" em Database → Extensions.
-- =============================================================================

-- 1. Habilitar pgvector
create extension if not exists vector;

-- 2. Tabela de embeddings dos transcripts (uma linha por transcript ou por chunk)
-- Dimensão 1536 = OpenAI text-embedding-3-small; use 384 para text-embedding-3-small com dimensions=384 ou gte-small
create table if not exists public.voice_transcript_embeddings (
  id uuid primary key default gen_random_uuid(),
  transcript_id uuid references public.voice_transcripts(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  content text not null,
  embedding vector(1536) not null,
  created_at timestamptz default now()
);

comment on table public.voice_transcript_embeddings is 'Embeddings dos voice_transcripts para busca semântica / RAG (perguntas à IA)';

alter table public.voice_transcript_embeddings enable row level security;

-- 3. Índices
create index if not exists idx_transcript_embeddings_user_id
  on public.voice_transcript_embeddings(user_id);
create index if not exists idx_transcript_embeddings_created_at
  on public.voice_transcript_embeddings(created_at desc);

-- Índice para busca por similaridade (cosine distance). Ajuste listas_size se tiver muitos registros.
create index if not exists idx_transcript_embeddings_hnsw
  on public.voice_transcript_embeddings
  using hnsw (embedding vector_cosine_ops)
  with (m = 16, ef_construction = 64);

-- 4. RLS: acesso sem login (qualquer um pode ler e escrever)
drop policy if exists "Users can manage their transcript embeddings" on public.voice_transcript_embeddings;

create policy "Anyone can insert transcript embeddings"
  on public.voice_transcript_embeddings for insert with check (true);

create policy "Anyone can select transcript embeddings"
  on public.voice_transcript_embeddings for select using (true);

create policy "Anyone can update transcript embeddings"
  on public.voice_transcript_embeddings for update using (true) with check (true);

create policy "Anyone can delete transcript embeddings"
  on public.voice_transcript_embeddings for delete using (true);

-- =============================================================================
-- Uso:
-- 1. Ao salvar um transcript, gere o embedding (ex.: OpenAI Embeddings API) e insira aqui.
-- 2. Para "perguntas do dia": filtre por data em created_at e use a função abaixo.
--
-- Exemplo de busca por similaridade (cosine, sem login):
--   select id, content, 1 - (embedding <=> $1::vector) as similarity
--   from voice_transcript_embeddings
--   where created_at >= current_date
--     and created_at < current_date + interval '1 day'
--   order by embedding <=> $1::vector
--   limit 5;
-- ($1 = embedding da pergunta do usuário)
-- =============================================================================

-- 5. Função auxiliar: busca semântica nos transcripts do dia (opcional)
create or replace function public.search_transcript_embeddings_of_day(
  query_embedding vector(1536),
  match_count int default 5,
  target_date date default current_date
)
returns table (
  id uuid,
  transcript_id uuid,
  content text,
  similarity float
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    e.id,
    e.transcript_id,
    e.content,
    1 - (e.embedding <=> query_embedding) as similarity
  from public.voice_transcript_embeddings e
  where e.created_at >= target_date
    and e.created_at < target_date + interval '1 day'
  order by e.embedding <=> query_embedding
  limit match_count;
end;
$$;
