-- Schema completo del database Registro presenze: concatenazione degli script
-- supabase/01..07 nell ordine di esecuzione (generato il 2026-09-09).


-- =============================== supabase/01-schema.sql ===============================
-- ============================================================================
-- Registro presenze — Schema Supabase (Postgres)
-- Passo 1 dell'ordine di costruzione (spec-claude-code.md, sez. 4 e 10).
-- Da eseguire UNA volta nel SQL Editor del progetto Supabase (regione UE).
-- Contenuto: tabelle + vincoli + RLS + trigger primo accesso + indici.
-- ============================================================================

-- ============================================================ 1. TABELLE

-- ---- profiles: 1 riga per utente (creata dal trigger al primo accesso)
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  nome       text,
  creato_il  timestamptz not null default now()
);

-- ---- impostazioni: 1 riga per utente (configurazione globale)
-- Mappa DB.startDate, DB.yearLabel, DB.initialBalanceMin del prototipo.
create table public.impostazioni (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  data_inizio_aa     date,
  anno_label         text,
  saldo_iniziale_min int  not null default 0,
  studio_default_min int  not null default 0,
  notifiche          jsonb not null default '{}'::jsonb
);

-- ---- timbrature: 1 riga per giorno
-- Mappa DB.entries[data] e DB.skipDays[data] (rimosso = true).
-- attivita    = e.act   (id del catalogo attività: presenza, ferie, studio, ...)
-- permesso_min= e.ph    (permesso orario, in minuti)
-- studio_min  = e.studyMin (ore studio del giorno, in minuti — campo del
--               prototipo non elencato nella specifica, aggiunto per non
--               perdere dati)
create table public.timbrature (
  id           bigint generated always as identity primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  data         date not null,
  attivita     text,
  m1in         time,
  m1out        time,
  m2in         time,
  m2out        time,
  permesso_min int,
  studio_min   int,
  nota         text,
  rimosso      boolean not null default false,
  unique (user_id, data)
);

-- ---- periodi: orari a periodi di validità (presenza e studio)
-- Mappa DB.schedulePeriods / DB.studyPeriods.
-- valido_dal null = "dall'inizio" (il prototipo usa from:'').
-- slots = per ogni giorno della settimana {start, end, pausa}; il campo
-- "schedule" (minuti d'obbligo per giorno) NON si salva: il prototipo lo
-- ricava da slots (end - start - pausa) e il client lo ricalcola al load.
create table public.periodi (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo       text not null check (tipo in ('presenza', 'studio')),
  valido_dal date,
  slots      jsonb not null default '{}'::jsonb
);

-- ---- diritti_permessi: limiti/diritti (ferie, paternità, ...)
-- Mappa DB.entitlements. etichetta = label del prototipo (serve salvarla:
-- "Ferie anno precedente" non esiste nel catalogo attività e non è derivabile).
create table public.diritti_permessi (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo       text not null,
  etichetta  text,
  unita      text not null check (unita in ('gg', 'ore')),
  totale     numeric not null default 0,
  gia_fruito numeric not null default 0,
  ordine     int not null default 0,
  unique (user_id, tipo)
);

-- ---- autorizzazioni: eccedenza autorizzata a saldo, per settimana
-- Mappa DB.authorized[lunedì].
create table public.autorizzazioni (
  id        bigint generated always as identity primary key,
  user_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  settimana date not null,          -- lunedì della settimana
  minuti    int  not null,
  unique (user_id, settimana)
);

-- ---- persone: calendario "Registro attività"
-- Mappa DB.people. colore = colore assegnato dalla palette del prototipo.
-- docente_id = teacherId (alunno associato a un docente); set null perché
-- l'app impedisce comunque di eliminare un docente con alunni associati.
-- unique (user_id, id): bersaglio delle FK composite di docente_id ed
-- eventi.persona_id — la FK semplice su id NON basterebbe, perché il controllo
-- di chiave esterna scavalca la RLS e permetterebbe di puntare a persone di
-- un altro utente. La coppia (user_id, id) vincola il riferimento alle
-- proprie righe.
create table public.persone (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome       text not null,
  ruolo      text not null check (ruolo in ('docente', 'alunno')),
  colore     text,
  docente_id bigint,
  unique (user_id, id),
  foreign key (user_id, docente_id) references public.persone (user_id, id)
    on delete set null (docente_id)
);

-- ---- eventi: attività del calendario
-- Mappa DB.events. Oltre ai campi della specifica, il prototipo ha:
-- ripetizione ('weekly' | null = singola), fino_al (fine serie),
-- avviso_min (minuti di preavviso notifica, null = nessuno),
-- conta_docente (le ore con l'alunno contano anche per il docente).
-- persona_id on delete cascade: l'app blocca già in UI l'eliminazione di una
-- persona con attività collegate; il cascade garantisce la pulizia a livello DB.
-- FK composita (user_id, persona_id): come per persone.docente_id, impedisce
-- di collegare un evento a una persona di un altro utente.
create table public.eventi (
  id            bigint generated always as identity primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  data          date not null,
  ora_inizio    time not null,
  ora_fine      time not null,
  tipo          text,
  persona_id    bigint,
  foreign key (user_id, persona_id) references public.persone (user_id, id)
    on delete cascade,
  ripetizione   text check (ripetizione in ('weekly')),
  fino_al       date,
  avviso_min    int,
  conta_docente boolean not null default false,
  nota          text
);

-- ============================================================ 2. RLS
-- Ogni utente legge e scrive SOLO le proprie righe. (select auth.uid()) invece
-- di auth.uid() nudo: Postgres lo valuta una volta per query, non per riga.

-- ---- profiles (condizione su id, non su user_id)
alter table public.profiles enable row level security;
create policy "solo il proprio profilo" on public.profiles
  for all
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---- impostazioni
alter table public.impostazioni enable row level security;
create policy "solo i propri dati" on public.impostazioni
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---- timbrature
alter table public.timbrature enable row level security;
create policy "solo i propri dati" on public.timbrature
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---- periodi
alter table public.periodi enable row level security;
create policy "solo i propri dati" on public.periodi
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---- diritti_permessi
alter table public.diritti_permessi enable row level security;
create policy "solo i propri dati" on public.diritti_permessi
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---- autorizzazioni
alter table public.autorizzazioni enable row level security;
create policy "solo i propri dati" on public.autorizzazioni
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---- persone
alter table public.persone enable row level security;
create policy "solo i propri dati" on public.persone
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---- eventi
alter table public.eventi enable row level security;
create policy "solo i propri dati" on public.eventi
  for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ============================================================ 3. TRIGGER PRIMO ACCESSO
-- Alla creazione dell'utente in auth.users (invito accettato) crea in
-- automatico la riga di profilo e quella di impostazioni.
-- security definer: gira coi permessi del proprietario, perché al momento
-- dell'insert non c'è una sessione utente che passi la RLS.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;

  insert into public.impostazioni (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================ 4. INDICI
-- La RLS filtra sempre per user_id: un indice per tabella evita scan completi.
-- timbrature e autorizzazioni sono già coperte dai vincoli UNIQUE(user_id, ...),
-- diritti_permessi da UNIQUE(user_id, tipo), profiles/impostazioni dalla PK.

create index periodi_user_idx on public.periodi (user_id, tipo);
create index persone_user_idx on public.persone (user_id);
create index eventi_user_idx  on public.eventi (user_id, data);


-- =============================== supabase/02-grants.sql ===============================
-- ============================================================================
-- Registro presenze — Permessi dei ruoli API (da eseguire dopo 01-schema.sql)
-- I progetti Supabase recenti non concedono più i permessi DML di default:
-- questo script dà al ruolo `authenticated` (utenti loggati) il minimo che
-- serve all'app — la RLS resta il vero confine tra un utente e l'altro.
-- Il ruolo `anon` (non loggati) resta senza alcun accesso: voluto.
-- ============================================================================

-- Utenti loggati: lettura/scrittura sulle tabelle (filtrate riga per riga
-- dalla RLS) e uso delle sequenze degli id generati.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Stessi permessi anche su eventuali tabelle/sequenze future.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

-- Igiene: via i permessi superflui presenti di default. TRUNCATE in
-- particolare NON è soggetto alla RLS (svuota l'intera tabella).
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;


-- =============================== supabase/03-archivi.sql ===============================
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


-- =============================== supabase/04-masterclass-straordinario.sql ===============================
-- ============================================================================
-- Registro presenze — Masterclass e straordinario pagato (dopo 01, 02, 03)
-- timbrature.masterclass_min : minuti della giornata dedicati a Masterclass
--                              (funzioni aggiuntive, pagate come straordinario)
-- autorizzazioni.pagati_min  : ore in piu della settimana autorizzate come
--                              straordinario PAGATO (a parte dal saldo);
--                              "minuti" resta lo straordinario A CREDITO
-- ============================================================================

alter table public.timbrature    add column if not exists masterclass_min int;
alter table public.autorizzazioni add column if not exists pagati_min int not null default 0;


-- =============================== supabase/05-masterclass-oltre-tetto.sql ===============================
-- ============================================================================
-- Registro presenze — Masterclass oltre il tetto delle 9h (dopo 01..04)
-- autorizzazioni.mc_oltre_min : minuti di Masterclass oltre il tetto
--                               settimanale autorizzati (0 = "no": come mai
--                               fatti; null = domanda non ancora risposta)
-- autorizzazioni.minuti        : diventa nullable, null = nessuna risposta
--                               sullo straordinario ordinario
-- ============================================================================

alter table public.autorizzazioni alter column minuti drop not null;
alter table public.autorizzazioni add column if not exists mc_oltre_min int;


-- =============================== supabase/06-richieste.sql ===============================
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


-- =============================== supabase/07-periodi-valido-al.sql ===============================
-- ============================================================================
-- Registro presenze — Fine facoltativa di un periodo di orario (dopo 01..06)
-- periodi.valido_al : lunedi' dell'ultima settimana in cui vale il periodo;
--                     null = fino al cambio successivo
-- ============================================================================

alter table public.periodi add column if not exists valido_al date;

