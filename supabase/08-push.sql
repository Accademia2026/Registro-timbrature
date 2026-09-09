-- ============================================================================
-- Registro presenze — Notifiche push (da eseguire dopo 01..07)
-- push_subscriptions : un'iscrizione per dispositivo (endpoint del browser)
-- avvisi_inviati     : memoria degli avvisi già spediti (niente doppioni)
-- La funzione server "invia-avvisi" legge con la chiave di servizio (salta la
-- RLS); l'app scrive solo le proprie iscrizioni.
-- ============================================================================

create table public.push_subscriptions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  endpoint    text not null,
  p256dh      text not null,
  auth        text not null,
  dispositivo text,
  creato_il   timestamptz not null default now(),
  unique (user_id, endpoint)
);

alter table public.push_subscriptions enable row level security;
create policy "solo i propri dati" on public.push_subscriptions
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table public.avvisi_inviati (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  evento_id   bigint not null,
  giorno      date not null,
  inviato_il  timestamptz not null default now(),
  unique (user_id, evento_id, giorno)
);

alter table public.avvisi_inviati enable row level security;
create policy "solo lettura dei propri avvisi" on public.avvisi_inviati
  for select
  using (user_id = (select auth.uid()));

create index push_subscriptions_user_idx on public.push_subscriptions (user_id);
create index avvisi_inviati_giorno_idx on public.avvisi_inviati (giorno);

grant select, insert, update, delete on public.push_subscriptions to authenticated;
grant select on public.avvisi_inviati to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke truncate, references, trigger on public.push_subscriptions, public.avvisi_inviati from anon, authenticated;
