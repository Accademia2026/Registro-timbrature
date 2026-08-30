# Piano — Registro presenze con Supabase (versione con account)

Documento di pianificazione per la versione con database. Da rileggere e, quando
il piano convince, passare a **Claude Code** per la costruzione. La logica di
calcolo attuale (pausa automatica, tetto 9h, priorità ferie, orari a periodi,
saldo) **si riusa quasi tutta**: cambia solo il salvataggio, che da `localStorage`
passa a chiamate al database.

---

## 1. Architettura

- **File statici** (l'app: HTML/JS/CSS) → ospitati gratis su **GitHub Pages**
  (o Netlify/Cloudflare Pages). Restano installabili come **PWA**.
- **Backend** → **Supabase**: database Postgres + autenticazione + API già pronte,
  chiamate direttamente dal browser tramite il client JS di Supabase.
- **Nessun server proprio, nessun Vercel.** Supabase sostituisce il backend, non
  l'hosting dei file statici (che comunque è gratuito).
- **Regione del progetto Supabase: UE (Francoforte)** — obbligatorio per il GDPR.

Schema a blocchi:

```
[ PWA su GitHub Pages ]  ──►  [ Supabase: Auth + Postgres + RLS ]
      (file statici)              (login email, dati per-utente)
```

---

## 2. Autenticazione — email + password, SOLO SU INVITO

- **Metodo scelto:** email + password.
- **Accesso solo su invito:** la registrazione libera è **disattivata**
  ("Allow new users to sign up" spento). Nessuno crea account da solo.
- **Aggiungere un collega:** dal pannello Supabase → Authentication → Users →
  **"Invite user"** con la sua email. Supabase invia la mail d'invito.
- **Flusso del collega:** riceve l'invito → clic sul link → **imposta la password**
  su una pagina dell'app → account attivo → poi accede con email + password.
- Il link d'invito rimanda a una **pagina "imposta password"** dell'app: si
  configura l'URL di ritorno dell'invito (redirect URL) e la pagina chiama
  `updateUser({ password })`.
- Flussi da prevedere nell'app: **login**, reset password, logout, imposta-password
  (da invito). **Niente schermata di registrazione.**
- **Offboarding:** eliminando l'utente dal pannello si cancellano anche i suoi dati
  (chiavi esterne `on delete cascade`, sez. 4).
- Al primo accesso si crea in automatico la riga in `profiles`/`impostazioni`
  (trigger Postgres, sez. 4.2).
- **Ogni utente vede solo i propri dati** grazie alle policy RLS (sez. 4).

---

## 2-bis. Distribuzione e primo accesso

**Cos'è l'app:** una web-app a un **indirizzo unico** (GitHub Pages), uguale per
tutti; parla con Supabase per dati e login. Non si scarica da alcuno store.

**Cosa fai tu (admin), una volta:**
1. Disattivi la registrazione libera in Supabase (accesso solo su invito).
2. Pubblichi l'app → ottieni l'indirizzo (es. `https://tuonome.github.io/registro/`).

**Per ogni collega:**
1. Lo inviti dal pannello Supabase (email).
2. (Facoltativo) gli mandi anche il link dell'app + due righe di istruzioni / un QR.

**Cosa fa il collega:**
1. Riceve la mail d'invito, tocca il link, **imposta la password**.
2. Apre l'app, **"Aggiungi a schermata Home" / "Installa"** (icona + schermo intero).
3. Accede con email + password. Vede solo i propri dati; se cambia telefono,
   riaccede e ritrova tutto.

**Aggiornamenti:** ripubblichi sullo stesso indirizzo → tutti hanno la versione
nuova alla successiva apertura; i dati nel database restano intatti.

---


## 3. Modello dati (tabelle Postgres)

Principio: le entità ad alto volume e interrogabili sono **normalizzate**; la
configurazione a basso volume può stare in campi `jsonb`. Ogni tabella ha
`user_id` che collega all'utente autenticato.

### `profiles` — 1 riga per utente
| campo | tipo | note |
|---|---|---|
| id | uuid (PK) | = `auth.uid()` |
| email | text | |
| nome | text | facoltativo |
| creato_il | timestamptz | default now() |

### `impostazioni` — 1 riga per utente (configurazione globale)
| campo | tipo | note |
|---|---|---|
| user_id | uuid (PK, FK) | |
| data_inizio_aa | date | inizio anno accademico |
| anno_label | text | es. "[AAAA]/[AA]" (calcolato) |
| saldo_iniziale_min | int | saldo di partenza in minuti (con segno) |
| studio_default_min | int | ore studio consultive di default |
| notifiche | jsonb | promemoria/opzioni |

### `timbrature` — 1 riga per giorno
| campo | tipo | note |
|---|---|---|
| id | bigint (PK) | |
| user_id | uuid (FK) | |
| data | date | |
| attivita | text | id attività (presenza, ferie, ...) |
| m1in, m1out, m2in, m2out | time | le due coppie entrata→uscita |
| permesso_min | int | ore permesso orario (se previsto) |
| nota | text | |
| rimosso | bool | default false (giorno tolto dall'obbligo) |
| **vincolo** | | UNIQUE(user_id, data) |

### `periodi` — orari a periodi di validità (presenza e studio)
| campo | tipo | note |
|---|---|---|
| id | bigint (PK) | |
| user_id | uuid (FK) | |
| tipo | text | 'presenza' \| 'studio' |
| valido_dal | date | lunedì di inizio validità (vuoto = dall'inizio) |
| slots | jsonb | per ogni giorno: {start, end, pausa} |

### `diritti_permessi` — limiti/diritti (ferie, paternità, ...)
| campo | tipo | note |
|---|---|---|
| id | bigint (PK) | |
| user_id | uuid (FK) | |
| tipo | text | |
| unita | text | 'gg' \| 'ore' |
| totale | numeric | |
| gia_fruito | numeric | quota fruita prima dell'uso dell'app |
| ordine | int | |

### `autorizzazioni` — eccedenza autorizzata a saldo, per settimana
| campo | tipo | note |
|---|---|---|
| id | bigint (PK) | |
| user_id | uuid (FK) | |
| settimana | date | lunedì della settimana |
| minuti | int | eccedenza autorizzata |
| **vincolo** | | UNIQUE(user_id, settimana) |

### (Fase 2) `persone` ed `eventi` — per la vista "Registro attività"
Da aggiungere solo quando si porta anche il calendario. Struttura analoga con
`user_id`, e per `eventi`: data/e, fascia oraria, tipo, persona collegata.

---

## 4. Sicurezza — Row Level Security (RLS)

Principio: anche condividendo lo stesso database, **ognuno legge e scrive solo le
proprie righe**. La RLS di Postgres è ciò che lo garantisce. Attenzione: sulle
tabelle nuove la RLS è **disattivata di default** — va abilitata su **ogni**
tabella, altrimenti i dati sono esposti tramite l'API pubblica.

### 4.1 Policy RLS concrete (SQL pronto)

Per ogni tabella con `user_id`: si imposta `user_id` in automatico al valore
dell'utente autenticato, si abilita la RLS e si crea una policy unica che copre
lettura e scrittura.

```sql
-- ================= TIMBRATURE =================
alter table timbrature alter column user_id set default auth.uid();
alter table timbrature enable row level security;
create policy "solo i propri dati" on timbrature
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ================= IMPOSTAZIONI =================
alter table impostazioni alter column user_id set default auth.uid();
alter table impostazioni enable row level security;
create policy "solo i propri dati" on impostazioni
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ================= PERIODI =================
alter table periodi alter column user_id set default auth.uid();
alter table periodi enable row level security;
create policy "solo i propri dati" on periodi
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ================= DIRITTI_PERMESSI =================
alter table diritti_permessi alter column user_id set default auth.uid();
alter table diritti_permessi enable row level security;
create policy "solo i propri dati" on diritti_permessi
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ================= AUTORIZZAZIONI =================
alter table autorizzazioni alter column user_id set default auth.uid();
alter table autorizzazioni enable row level security;
create policy "solo i propri dati" on autorizzazioni
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ================= PROFILES =================
alter table profiles enable row level security;
create policy "solo il proprio profilo" on profiles
  for all using (id = auth.uid()) with check (id = auth.uid());
```

- `using (...)` protegge **lettura/aggiornamento/cancellazione** (vedi solo le tue righe).
- `with check (...)` protegge **inserimento/aggiornamento** (non puoi creare righe
  intestate a un altro utente).
- Le chiavi esterne verso `auth.users(id)` vanno con **`on delete cascade`**, così
  cancellando l'account si cancellano tutti i suoi dati (diritto all'oblio GDPR).

### 4.2 Creazione automatica di profilo e impostazioni al primo accesso

```sql
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  insert into public.impostazioni (user_id) values (new.id);
  return new;
end; $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

### 4.3 Chiavi e configurazione (responsabilità nostra)

- Nel browser si usa **solo la chiave pubblica (anon)**, protetta dalla RLS.
- La chiave **`service_role`** (da amministratore, scavalca la RLS) **non deve mai
  finire nel client**: solo lato server (Edge Function), se e quando servirà.
- **Regione UE** (Francoforte) scelta alla creazione del progetto (non cambiabile dopo).
- **Firma del DPA** con Supabase.
- Autenticazione: **conferma email obbligatoria**, lunghezza minima password,
  protezione password compromesse, limiti sui tentativi; **MFA** opzionale per gli utenti.

### 4.4 Checklist di collaudo della sicurezza

Da eseguire **prima del rilascio**, con due utenti di prova A e B:

- [ ] **RLS attiva su tutte le tabelle** (dashboard → Security Advisor: nessuna tabella "RLS disabled").
- [ ] A inserisce dati; **B non riesce a leggerli** via API.
- [ ] B **non riesce a modificare né cancellare** le righe di A.
- [ ] Senza login (chiamata anonima), le query **non restituiscono nulla**.
- [ ] Un inserimento con `user_id` falsificato (di un altro) **viene rifiutato**.
- [ ] La chiave **`service_role` non è presente** nel bundle del client (ricerca nel codice pubblicato).
- [ ] La conferma **email è richiesta** alla registrazione.
- [ ] **Eliminazione account** → spariscono tutte le righe collegate (cascade).
- [ ] Progetto nella **regione UE** verificato.
- [ ] Eseguito il **Security Advisor / linter** di Supabase senza segnalazioni critiche.

---

## 5. Connessione (online-first)

- L'app legge/scrive su Supabase quando c'è rete. Per timbrature inserite durante
  la giornata, di norma si è online.
- Resta **installabile come PWA** (icona, schermo intero), ma **richiede connessione**.
- **Funzionamento offline NON previsto** (scelta presa): niente cache/coda di
  sincronizzazione. Meno complessità, meno cose da collaudare.

---

## 6. GDPR — checklist (dati personali di dipendenti pubblici)

- [ ] Progetto Supabase in **regione UE** (Francoforte).
- [ ] **Informativa privacy** in-app (cosa si raccoglie, perché, per quanto).
- [ ] **Base giuridica** del trattamento chiarita.
- [ ] **Accordo sul trattamento dei dati (DPA)** con Supabase come responsabile.
- [ ] **Minimizzazione**: si raccolgono solo email + dati di timbratura, nulla di superfluo.
- [ ] **Diritto di cancellazione**: "elimina account" che cancella a cascata tutti i dati dell'utente.
- [ ] **Conservazione (retention)**: definire per quanto tempo si tengono i dati.
- [ ] Backup e accessi documentati.

> Nota: la responsabilità legale passa da "app mia sul mio telefono" a "gestisco
> dati di terzi su un servizio". Va gestita con attenzione prima del rilascio pubblico.

---

## 7. Costi — scelta: piano GRATUITO a costo zero

**Decisione presa: Supabase, piano gratuito.** I due limiti del free (pausa e
niente backup automatici) si neutralizzano **senza pagare**, con due automazioni
gratuite. I 25 $/mese del Pro restano un'opzione futura, non un obbligo.

Il gratuito include: 500 MB database, 50.000 utenti attivi/mese, uso commerciale
permesso, senza carta di credito — ampiamente oltre i numeri di un conservatorio.

### 7.1 Evitare la pausa (a costo zero)
La pausa scatta dopo **7 giorni senza attività sul database**. Si evita tenendolo
"sveglio" con un **ping giornaliero**:
- **GitHub Actions** (gratuito): un workflow schedulato una volta al giorno che
  esegue una query minima (es. `select 1` o legge una riga di servizio). Reset del
  timer, zero costi.
- In alternativa un monitor gratuito (es. **Uptime Robot**) che chiama un endpoint
  che tocca il database.
- Si imposta una volta e non si tocca più.

### 7.2 Backup automatici (a costo zero)
Il free non fa backup automatici: li facciamo noi con un **export programmato**.
- **GitHub Actions** schedulato (es. settimanale) che esegue `pg_dump` del database
  e salva il file come artifact/nel repo privato (o su Drive).
- Così hai una copia periodica recuperabile, senza il piano Pro.

### 7.3 Quando (eventualmente) passare a Pro
Solo se un domani vuoi **backup gestiti + Point-in-Time Recovery + zero pausa senza
automazioni**: Pro ~25 $/mese. Per ora **non serve**.

---

## 8. Migrazione dai dati locali

- L'app attuale esporta un **backup JSON**. Si prepara uno **script una-tantum**
  che legge quel file e popola le tabelle Supabase dell'utente.
- Così chi ha già usato la versione locale non riparte da zero.

---

## 9. Passi operativi (con Claude Code)

1. Creare il progetto Supabase (regione UE) e le tabelle + policy RLS (sezioni 3–4).
2. Impostare l'autenticazione email (sezione 2).
3. Portare l'app: sostituire `localStorage` con il client Supabase, aggiungere le
   schermate di login, riusare la logica di calcolo esistente.
4. Deploy dei file statici su GitHub Pages; test come PWA.
5. Informativa + checklist GDPR (sezione 6).
6. Migrazione dei dati di test (sezione 8).
7. Rilascio ai colleghi.

---

## Riepilogo delle decisioni — TUTTE PRESE ✓

- **Piattaforma**: Supabase (Postgres + Auth + RLS), file statici su GitHub Pages.
- **Piano**: gratuito, a costo zero, con ping anti-pausa + export automatico (sez. 7).
- **Login**: **email + password**.
- **Prima versione**: timbrature/permessi/impostazioni **+ calendario "Registro
  attività"**. **Online-first: il funzionamento offline NON è previsto.**

**Ordine di costruzione consigliato** (per ridurre i rischi):
1. Tabelle + RLS + login email/password (fondamenta sicure).
2. Viste core: timbrature, permessi, impostazioni (riuso logica esistente).
3. Calendario "Registro attività" (tabelle `persone`/`eventi`).
4. Deploy su GitHub Pages + ping anti-pausa + export automatico.
5. Migrazione dati di test + collaudo sicurezza (sez. 4.4) + checklist GDPR (sez. 6).


