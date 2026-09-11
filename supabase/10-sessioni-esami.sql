-- ============================================================================
-- Registro presenze — Sessioni d'esame dell'anno (da eseguire dopo 01..09)
-- Elenco consultabile nella sezione Orario di lavoro: titolo, periodo, nota.
-- ============================================================================

create table public.sessioni_esami (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  titolo     text not null,
  dal        date not null,
  al         date not null,
  nota       text,
  creata_il  timestamptz not null default now()
);

alter table public.sessioni_esami enable row level security;
create policy "solo i propri dati" on public.sessioni_esami
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create index sessioni_esami_user_idx on public.sessioni_esami (user_id, dal);

grant select, insert, update, delete on public.sessioni_esami to authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated;
revoke truncate, references, trigger on public.sessioni_esami from anon, authenticated;
