-- ============================================================
-- APP FOUNDATION — temel şema
-- ============================================================
-- Supabase SQL Editor'de bir kez çalıştır (veya `supabase db push`).
-- İçerik:
--   1. Eklentiler (pgvector)
--   2. items tablosu (örnek ana varlık) + RLS
--   3. Full-text arama kolonu (otomatik üretilen tsvector)
--   4. hybrid_search_items: full-text + semantik, RRF ile birleştirme
--
-- Yeni uygulamada `items` tablosunu kendi ana varlığına göre yeniden
-- adlandır/genişlet. delete-account fonksiyonuna da yeni tabloları ekle.
-- ============================================================

create extension if not exists vector;

-- ------------------------------------------------------------
-- items
-- ------------------------------------------------------------
create table if not exists public.items (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users (id) on delete cascade,
  title                  text not null default '',
  content                text,
  url                    text,
  note                   text,
  tags                   text[] not null default '{}',
  embedding              vector(768),
  -- true: vektör Gemini değil OpenRouter fallback modelinden geldi
  -- (farklı vektör uzayı; ileride Gemini ile yeniden üretilebilir).
  embedding_is_fallback  boolean not null default false,
  -- 'simple' sözlüğü dilden bağımsızdır (TR/EN/PT/ES karışık içerik için).
  search_tsv             tsvector generated always as (
    to_tsvector('simple',
      coalesce(title, '') || ' ' ||
      coalesce(content, '') || ' ' ||
      coalesce(note, '') || ' ' ||
      array_to_string(tags, ' '))
  ) stored,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists items_user_created_idx
  on public.items (user_id, created_at desc);
create index if not exists items_search_tsv_idx
  on public.items using gin (search_tsv);
create index if not exists items_embedding_idx
  on public.items using hnsw (embedding vector_cosine_ops);

-- updated_at otomatik güncelleme
create or replace function public.set_updated_at()
returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists items_set_updated_at on public.items;
create trigger items_set_updated_at
  before update on public.items
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- Row Level Security: herkes sadece kendi satırlarını görür/değiştirir
-- ------------------------------------------------------------
alter table public.items enable row level security;

drop policy if exists "items_select_own" on public.items;
create policy "items_select_own" on public.items
  for select using (auth.uid() = user_id);

drop policy if exists "items_insert_own" on public.items;
create policy "items_insert_own" on public.items
  for insert with check (auth.uid() = user_id);

drop policy if exists "items_update_own" on public.items;
create policy "items_update_own" on public.items
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "items_delete_own" on public.items;
create policy "items_delete_own" on public.items
  for delete using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- Hybrid search (Reciprocal Rank Fusion)
-- query_embedding null ise sadece full-text sonuçları döner.
-- security invoker: RLS geçerli kalır, match_user_id ek filtre.
-- ------------------------------------------------------------
create or replace function public.hybrid_search_items(
  query_text       text,
  query_embedding  vector(768) default null,
  match_user_id    uuid default auth.uid(),
  full_text_weight float default 1.0,
  semantic_weight  float default 1.5,
  rrf_k            int   default 50,
  match_count      int   default 20
)
returns setof public.items
language sql stable
security invoker
as $$
  with full_text as (
    select id,
           row_number() over (
             order by ts_rank_cd(search_tsv, websearch_to_tsquery('simple', query_text)) desc
           ) as rank_ix
    from public.items
    where user_id = match_user_id
      and search_tsv @@ websearch_to_tsquery('simple', query_text)
    order by rank_ix
    limit least(match_count, 30) * 2
  ),
  semantic as (
    select id,
           row_number() over (order by embedding <=> query_embedding) as rank_ix
    from public.items
    where user_id = match_user_id
      and query_embedding is not null
      and embedding is not null
    order by rank_ix
    limit least(match_count, 30) * 2
  )
  select i.*
  from public.items i
  join (
    select
      coalesce(ft.id, sem.id) as id,
      coalesce(1.0 / (rrf_k + ft.rank_ix),  0) * full_text_weight
    + coalesce(1.0 / (rrf_k + sem.rank_ix), 0) * semantic_weight as score
    from full_text ft
    full outer join semantic sem on ft.id = sem.id
  ) ranked on i.id = ranked.id
  order by ranked.score desc
  limit match_count;
$$;
