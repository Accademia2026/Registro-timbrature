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
