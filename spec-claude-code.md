# Specifica tecnica per Claude Code — Registro presenze (versione Supabase)

Documento di consegna unico. Da aprire in **Claude Code** insieme al file
`registro-presenze.html` (l'app attuale, che è il **prototipo funzionante** da cui
riusare tutta la logica). Per il razionale esteso (costi, GDPR, distribuzione) vedi
`piano-supabase.md`.

---

## 0. Obiettivo

Trasformare l'app locale attuale (single-file HTML/JS, dati in `localStorage`) in
una web-app **multi-utente** con dati su **Supabase**, mantenendo **intatta la
logica di calcolo**. Ogni utente accede con **email + password (solo su invito)** e
vede **solo i propri dati**. Online-first (niente offline).

## 1. Principi

- **Riusare, non riscrivere**: la logica di calcolo dell'app attuale è collaudata.
  Si sostituisce **solo lo strato di salvataggio** (`localStorage` → Supabase) e si
  aggiunge l'**autenticazione**. Le funzioni di calcolo e le viste restano.
- **Poco codice, ma efficace**: niente framework pesante. **Vanilla JS + client
  `@supabase/supabase-js`**, file statici. Struttura semplice.
- **Sicurezza da subito**: RLS su ogni tabella (sez. 4) e collaudo (sez. 8).

## 2. Stack e hosting

- Frontend: HTML/CSS/JS (riuso dell'attuale), client `@supabase/supabase-js`
  (via CDN o npm).
- Backend: **Supabase** (Postgres + Auth + RLS), progetto in **regione UE (Francoforte)**.
- Hosting file statici: **GitHub Pages** (gratuito).
- Config pubblica nel client: **Project URL + Publishable key** (`sb_publishable_...`,
  erede della anon; pubblica, protetta da RLS). La **Secret key** (`sb_secret_...`,
  erede della service_role) **NON deve mai stare nel client** (solo lato server).
  N.B. Le chiavi legacy anon/service_role vengono deprecate entro fine 2026.

## 3. Struttura progetto (proposta)

```
/ (repo)
  index.html            # app (login + viste)
  /js
    supabase.js         # init client (URL + anon key)
    auth.js             # login, logout, reset, imposta-password (da invito)
    repo.js             # data layer: load/save verso Supabase (sostituisce Store)
    logica.js           # TUTTE le funzioni di calcolo riusate dall'app attuale
    ui/*.js             # render delle viste (riuso dall'app attuale)
  /.github/workflows
    keepalive.yml       # ping giornaliero anti-pausa
    backup.yml          # export (pg_dump) programmato
  manifest.webmanifest, sw.js, icone…   # PWA
```

## 4. Database — schema + RLS + trigger (SQL pronto)

### 4.1 Tabelle
- `profiles(id uuid pk = auth.uid(), email, nome, creato_il)`
- `impostazioni(user_id uuid pk, data_inizio_aa date, anno_label text, saldo_iniziale_min int, studio_default_min int, notifiche jsonb)`
- `timbrature(id bigint pk, user_id uuid, data date, attivita text, m1in time, m1out time, m2in time, m2out time, permesso_min int, nota text, rimosso bool default false, unique(user_id,data))`
- `periodi(id bigint pk, user_id uuid, tipo text /* 'presenza'|'studio' */, valido_dal date, slots jsonb)`
- `diritti_permessi(id bigint pk, user_id uuid, tipo text, unita text /* 'gg'|'ore' */, totale numeric, gia_fruito numeric, ordine int)`
- `autorizzazioni(id bigint pk, user_id uuid, settimana date, minuti int, unique(user_id,settimana))`
- `persone(id bigint pk, user_id uuid, nome text, ruolo text, docente_id bigint null)`  — calendario
- `eventi(id bigint pk, user_id uuid, data date, ora_inizio time, ora_fine time, tipo text, persona_id bigint null, nota text)` — calendario

Tutte le FK verso `auth.users(id)` con **`on delete cascade`** (diritto all'oblio).

### 4.2 RLS (per OGNI tabella con user_id)
```sql
alter table <tab> alter column user_id set default auth.uid();
alter table <tab> enable row level security;
create policy "solo i propri dati" on <tab>
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
```
Per `profiles` la condizione è `id = auth.uid()`.

### 4.3 Trigger primo accesso
```sql
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  insert into public.impostazioni (user_id) values (new.id);
  return new;
end; $$;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();
```

## 5. Autenticazione (email + password, SOLO su invito)

- In Supabase Auth: **disattivare la registrazione libera** ("Allow new users to sign up").
- Aggiungere utenti: dashboard → Authentication → **Invite user** (email).
- App: schermata **login** (email+password) + **reset password** + pagina
  **imposta-password** che gestisce il token dell'invito (`updateUser({ password })`).
  **Nessuna schermata di registrazione.**
- Configurare il **redirect URL** dell'invito → pagina imposta-password dell'app.
- Al login: caricare i dati dell'utente (sez. 6). Al logout: svuotare lo stato.

## 6. Data layer — sostituire `localStorage` con Supabase (parte chiave)

L'app attuale tiene tutto in un oggetto in memoria (`DB`) e lo salva come **un unico
blob** in `localStorage`. Va sostituito il **come** si carica/salva, **non** la forma
di `DB`: così viste e calcoli non cambiano.

### 6.1 Caricamento (al login)
`repo.loadAll(userId)` legge le righe dell'utente e **ricompone l'oggetto `DB`** con
la stessa forma di oggi:
| Tabella | → campo di `DB` |
|---|---|
| `impostazioni` | `DB.startDate`, `DB.yearLabel`, `DB.saldo`, studio default, notifiche |
| `timbrature` | `DB.entries[data]` (e `DB.skipDays[data]` se `rimosso`) |
| `periodi` (presenza/studio) | `DB.schedulePeriods` / `DB.studyPeriods` (da `slots`) |
| `diritti_permessi` | `DB.entitlements` |
| `autorizzazioni` | `DB.authorized[settimana]` |
| `persone` / `eventi` | `DB.people` / `DB.events` |

### 6.2 Salvataggio (per entità, non più a blob)
Sostituire le chiamate `save()` con **upsert mirati** sulla riga toccata:
- modifica timbratura di un giorno → `upsert timbrature` (chiave `user_id,data`);
- rimuovi/ripristina giorno → `timbrature.rimosso = true/false`;
- modifica orari a periodi → upsert/delete su `periodi`;
- modifica diritti permessi → upsert `diritti_permessi`;
- autorizza eccedenza → upsert `autorizzazioni` (chiave `user_id,settimana`);
- impostazioni → update `impostazioni`;
- eventi/persone → upsert/delete relativi.
- `user_id` è impostato in automatico (default `auth.uid()`), non va inviato dal client.
- Mantenere un piccolo **debounce** come oggi per non scrivere a ogni battuta.

### 6.3 Cosa RESTA identico (riuso diretto dall'app attuale)
NON riscrivere: tutte le funzioni di calcolo e le viste. In particolare:
- `presenceWork`, `dayWorkInfo`, `dayMinutes` (pausa automatica, tetto 9h);
- funzioni a periodi: `periodFor`, `scheduleForWeek`, `studyScheduleForWeek`,
  `presSlotsForWeek`, `obligationForWeek`, `expectedFor`, `studyDefaultFor`;
- `ferieAlloc` (priorità ferie anno precedente), `usage`;
- `weekTotal`, `runningBalance`, `authForWeek`;
- helper data/orari (`iso`, `parseISO`, `mondayOf`, `addDays`, `t2m`, `fmtHM`, `aaLabel`);
- il **render** delle viste (già in stile iOS) e il **tastierino**.
Questi leggono/scrivono l'oggetto `DB`: cambiando solo load/save, continuano a funzionare.

## 7. Deploy, anti-pausa e backup (costo zero)

- **GitHub Pages**: pubblicare la cartella; ottenere l'URL dell'app.
- **Anti-pausa** (`keepalive.yml`): GitHub Action schedulata **1×/giorno** che esegue
  una query minima su Supabase (mantiene il progetto attivo).
- **Backup** (`backup.yml`): GitHub Action schedulata (es. settimanale) che esegue
  `pg_dump` e salva il file come artifact / nel repo privato.

## 8. Collaudo sicurezza (prima del rilascio)

Con due utenti A e B:
- [ ] RLS attiva su tutte le tabelle (Security Advisor: nessuna "RLS disabled").
- [ ] B non legge/modifica/cancella i dati di A.
- [ ] Query anonima (senza login) → nessun dato.
- [ ] Insert con `user_id` di un altro → rifiutata.
- [ ] **Secret key** (ex `service_role`) **assente** dal bundle client.
- [ ] Registrazione libera **disattivata** (solo invito funziona).
- [ ] Eliminazione utente → dati cancellati a cascata.
- [ ] Progetto in **regione UE**.

## 9. GDPR (vedi `piano-supabase.md` sez. 6)

Regione UE; informativa privacy in-app; base giuridica; **DPA** con Supabase;
minimizzazione; diritto di cancellazione (elimina account → cascade); retention.

## 10. Ordine di costruzione

1. Progetto Supabase (UE) + tabelle + RLS + trigger (sez. 4).
2. Auth email/password **solo su invito** + pagina imposta-password (sez. 5).
3. Data layer `repo.js`: `loadAll` + upsert mirati (sez. 6).
4. Innesto: collegare load/save alle viste esistenti; le viste/calcoli restano.
5. Deploy GitHub Pages + `keepalive.yml` + `backup.yml` (sez. 7).
6. Import dati di test dal backup JSON dell'app locale.
7. Collaudo sicurezza (sez. 8) + checklist GDPR (sez. 9).
