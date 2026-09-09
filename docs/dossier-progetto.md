# Registro presenze — dossier di progetto

Documento di sintesi per chi deve **progettare** sull'app (per esempio il lato
amministrazione) senza leggere il codice. Aggiornato al 9 settembre 2026.

## 1. Che cos'è

App web mobile-first (PWA, installabile su iPhone e Android dalla schermata
Home) per il personale tecnico-amministrativo del Conservatorio di Musica
«Niccolò Piccinni» di Bari. Ogni utente registra le proprie timbrature,
permessi, straordinari e attività, e produce PDF per la segreteria.

- Pubblicata su GitHub Pages: https://accademia2026.github.io/Registro-timbrature/
- Repository (pubblico): https://github.com/Accademia2026/Registro-timbrature
- Backend: Supabase (Postgres + Auth), progetto in Europa.
- Oggi è **monoutente per riga**: ogni utente vede e modifica solo i propri
  dati (Row Level Security). Non esiste ancora un ruolo "amministrazione".

## 2. Architettura

| Pezzo | Dove | Note |
|---|---|---|
| Interfaccia | `index.html` (unico file: HTML, CSS, JS in un modulo) | ~5.500 righe, vanilla JS, nessun framework |
| Tema grafico | `css/tema.css` (ufficiale Controtempo, non si tocca) + `css/tema-controtempo.css` (adattamento) | chiaro/scuro |
| Accesso | `js/auth.js`, `js/supabase.js` | login email+password, **registrazione disabilitata**: gli utenti si creano dal pannello Supabase (invito) |
| Dati | `js/repo.js` | `loadAll()` ricompone l'oggetto `DB`; salvataggi mirati con debounce; import/export completo |
| Pagina reset password | `imposta-password.html` | |
| Database | `supabase/01-schema.sql` … `07-periodi-valido-al.sql` | eseguiti in ordine nel SQL Editor di Supabase |
| PDF | jsPDF + autotable da cdnjs, caricate al bisogno | condivisione nativa su iPhone |

Non ci sono service worker né notifiche push (in programma).

## 3. Modello dei dati (Supabase)

Tutte le tabelle hanno `user_id` (default `auth.uid()`) e la policy RLS
«solo i propri dati». Il ruolo `anon` non ha alcun permesso.

| Tabella | Contenuto | Campi principali |
|---|---|---|
| `profiles` | un profilo per utente (creato da trigger alla creazione dell'utente) | `id`, `email`, `nome` |
| `impostazioni` | una riga per utente | `data_inizio_aa`, `anno_label`, `saldo_iniziale_min`, `notifiche` (jsonb) |
| `timbrature` | una riga per giorno | `data`, `attivita` (id attività), `m1in/m1out/m2in/m2out` (orari), `permesso_min`, `studio_min`, `masterclass_min`, `nota`, `rimosso` |
| `periodi` | orario di lavoro a periodi, tipo `presenza` o `studio` | `valido_dal`, `valido_al` (null = fino al cambio successivo), `slots` jsonb per giorno `{start,end,pausa,mcs,mce}` (`mcs/mce` = fascia Masterclass, solo nel tipo presenza) |
| `diritti_permessi` | monte permessi annuo | `tipo`, `etichetta`, `unita` (gg/ore), `totale`, `gia_fruito`, `ordine` |
| `autorizzazioni` | risposte settimanali sullo straordinario | `settimana` (lunedì), `minuti` (a credito; null = non ancora deciso), `pagati_min`, `mc_oltre_min` (Masterclass oltre il tetto: null = non deciso, 0 = no) |
| `persone` | docenti e alunni del calendario | `nome`, `ruolo`, `colore`, `docente_id` |
| `eventi` | attività del calendario | `data`, `ora_inizio`, `ora_fine`, `persona_id` (null = attività libera), `tipo` (descrizione dell'attività libera), `ripetizione` (weekly), `fino_al`, `avviso_min`, `conta_docente`, `nota` |
| `archivi` | anni accademici chiusi | `anno_label`, `chiuso_il`, `saldo_finale_min`, `dati` (istantanea completa jsonb) |
| `richieste` | moduli inviati alla segreteria | `tipo` (`ferie_permesso`/`riposo`), `dal`, `al`, `stato` (inviata/autorizzata/rifiutata), `dati` jsonb, `creata_il` |

Convenzioni: settimane identificate dal lunedì in formato ISO; minuti interi
ovunque; unità `gg`/`ore` nel DB, `GG`/`ORE` nell'app; id numerici trattati
come stringhe nell'interfaccia.

## 4. Regole d'istituto implementate

Sono le regole confermate dall'utente pilota (personale T.A., CCNL AFAM).

- **Settimana ordinaria: 36 ore** = 24 di presenza + 12 di studio. Lo studio
  è un contatore separato: non entra mai nel saldo ore.
- **Orario di lavoro** a periodi ("Dall'inizio", poi variazioni "dalla
  settimana del …" con fine facoltativa). Regola di salvataggio: presenza +
  studio + Masterclass oltre le 9h = 36h, massimo 9h al giorno, nessuna
  sovrapposizione, totale ≤ 45h.
- **Saldo ore** (credito/debito), il cuore del sistema:
  - settimana sotto le ore dovute → **debito** automatico;
  - settimana sopra le ore dovute → **non** ripiana mai il debito da sola:
    l'app chiede sempre "A credito / Pagate / No". Solo "a credito" entra nel
    saldo; "pagate" va in un monte a parte; "no" = ore come mai fatte;
  - il credito si **arrotonda alla mezz'ora per difetto** (1h14 → 1h, 0h11 → 0);
  - **riposo compensativo**: attività "Compensazione" con ore prese dal saldo,
    che contano come presenza nella settimana e vengono scalate dal saldo.
- **Straordinario**: massimo 9h a settimana sulla somma ordinario + Masterclass
  (tetto 45h complessive).
- **Masterclass** (funzioni aggiuntive): ore segnate nel giorno con "di cui
  Masterclass"; pagate a parte, mai nel saldo, non ripianano mai il debito.
  Oltre le 9h l'app chiede se sono autorizzate: "sì" = pagate ed erodono la
  presenza ordinaria (debito), "no" = come mai fatte.
- **Permessi**: monte annuo per voce (valori CCNL Funzionari AFAM come
  riferimento), tutti per **anno accademico**; le ferie consumano prima quelle
  dell'anno precedente. Permessi a giorni valgono le ore dovute del giorno;
  permessi a ore riducono le ore dovute.
- **Chiusura anno**: archivio dell'anno, saldo finale → saldo iniziale del nuovo
  anno, ferie non godute → "ferie anno precedente", timbrature azzerate.
- Domenica non esiste; sabato solo se previsto dall'orario.

## 5. Funzioni dell'app (viste)

- **Riepilogo**: Timbra adesso; Andamento (riquadro apribile con saldo, settimane,
  straordinario, riposo, Masterclass, ferie, malattia, omesse: ogni voce apre
  l'elenco delle settimane); Saldo ore: movimenti (libro mastro crediti/debiti/
  riposi con filtri); Ultima settimana e menù delle altre.
- **Timbrature**: settimana con riquadro Presenza/Dovute/Credito/Studio,
  domande su straordinario e Masterclass, righe per giorno con editor
  (attività, quattro orari, permesso, "di cui Masterclass", note), tastierino,
  copia/incolla, azioni settimana.
- **Attività** (Registro attività): calendario settimanale con fasce presenza/
  studio/Masterclass, attività per docente/alunno o libere, ripetizione
  settimanale, avvisi, ore per persona, export .ics.
- **Permessi**: monte per voce con scheda "quando l'ho usato"; moduli
  ufficiali compilati (richiesta ferie/permesso, richiesta riposo
  compensativo) con condivisione e storico richieste (stato, rigenera PDF,
  inserimento giornate nel registro).
- **Impostazioni**: anno e saldo iniziale, orario di lavoro (periodi, PDF per la
  segreteria per ogni orario), limiti permessi, esportazione annuale per la
  segreteria (PDF a sezioni), chiusura anno e archivio, backup/import JSON,
  installazione.

## 6. Moduli e comunicazioni

- PDF **orario di servizio** ("con decorrenza dalla settimana del …" oppure
  "orario di servizio dal … al …" se temporaneo).
- PDF **prospetto presenze** annuale, completo o a sezioni.
- Moduli ufficiali replicati: **richiesta ferie/permesso** (al Direttore) e
  **richiesta riposo compensativo**. Invio: foglio di condivisione (Mail,
  WhatsApp); l'indirizzo della segreteria (gestionepersonale@consba.it) viene
  copiato negli appunti perché con un allegato il destinatario non si può
  precompilare.

## 7. Cosa manca / idee aperte

- **Lato amministrazione** (da progettare): ruoli (dipendente, segreteria,
  direzione), vista del personale, approvazione delle richieste dall'app,
  riepiloghi aggregati, eventuale firma/vidimazione, GDPR.
- Notifiche push (piano: tabella iscrizioni + service worker + Edge Function
  con VAPID + pianificatore).
- Keepalive del progetto Supabase (piano gratuito) e backup automatico su GitHub.
- Collaudo con due utenti; informativa GDPR.
- Altri moduli ufficiali oltre ai due presenti.

## 8. Vincoli e lezioni apprese

- Codice e database vanno pubblicati **insieme**: mai codice che scrive colonne
  non ancora create (è successo: variazioni di orario perse). I salvataggi
  "sostituisci tutto" ora inseriscono prima e cancellano dopo.
- Su iPhone la versione precedente resta in cache: chiudere e riaprire l'app.
- Nessuna chiave segreta nel codice: solo la chiave pubblica di Supabase; i
  permessi veri stanno nella RLS.
- L'utente pilota non è uno sviluppatore: le istruzioni operative (script SQL,
  pannello Supabase) vanno date passo per passo.
