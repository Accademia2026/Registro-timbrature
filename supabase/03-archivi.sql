-- ============================================================================
-- Registro presenze — Archivio anni chiusi (da eseguire dopo 01 e 02)
-- Ogni riga è un anno accademico chiuso: etichetta, saldo finale e l'istantanea
-- completa dei dati (jsonb), consultabile e scaricabile dall'app.
-- ============================================================================

create table public.archivi (
  id                bigint generated always as identity primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  anno_label        text not null,
  chiuso_il         timestamptz not null default now(),
  saldo_finale_min  int not null default 0,
  dati              jsonb not null
);

alter table public.archivi enable row level security;
create policy "solo i propri dati" on public.archivi
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create index archivi_user_idx on public.archivi (user_id, chiuso_il desc);

-- permessi espliciti (il default dovrebbe già coprire, ma meglio non fidarsi)
grant select, insert, update, delete on public.archivi to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke truncate, references, trigger on public.archivi from anon, authenticated;
