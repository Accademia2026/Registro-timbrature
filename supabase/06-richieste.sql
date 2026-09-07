-- ============================================================================
-- Registro presenze — Storico delle richieste (moduli inviati alla segreteria)
-- Da eseguire dopo 01..05. Una riga per modulo generato: tipo, periodo,
-- dati compilati (jsonb, pochi campi) e stato (inviata / autorizzata /
-- rifiutata). Occupa pochissimo: qualche centinaio di byte a richiesta.
-- ============================================================================

create table public.richieste (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo       text not null,                       -- 'ferie_permesso' | 'riposo'
  dal        date,
  al         date,
  stato      text not null default 'inviata',     -- inviata | autorizzata | rifiutata
  dati       jsonb not null,
  creata_il  timestamptz not null default now()
);

alter table public.richieste enable row level security;
create policy "solo i propri dati" on public.richieste
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create index richieste_user_idx on public.richieste (user_id, creata_il desc);

grant select, insert, update, delete on public.richieste to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke truncate, references, trigger on public.richieste from anon, authenticated;
