# Regole di orario, credito e debito

Modello consolidato il 13 settembre 2026 dalle risposte dell'utente. Sostituisce
le regole precedenti. È la specifica da cui riscrivere il motore di calcolo.

## 1. Monte ore settimanale

| Voce | Ore | Natura |
|---|---|---|
| Presenza ordinaria | 24 | dovute ogni settimana, sempre |
| Studio | 12 | intoccabili, contatore a parte, non si timbrano |
| Straordinario ordinario | fino a 9 | facoltativo, mai pagato |
| **Totale massimo** | **45** | limite di legge, non superabile |

La Masterclass sta fuori dal tetto delle 9 ore di straordinario, ma dentro il
tetto delle 45 ore complessive.

## 2. L'Orario di lavoro dice il tipo, le timbrature dicono la quantità

In Impostazioni → Orario di lavoro si configurano, giorno per giorno, le fasce:

- **presenza ordinaria**
- **studio** (non si timbra: è un contatore)
- **straordinario ordinario** (fascia dedicata)
- **Masterclass**

Una fascia configurata vale come attività già autorizzata.

**Nella giornata non si dichiara nulla: si timbra e basta.** Il tipo di ora
(ordinario, straordinario, Masterclass) lo decide l'Orario di servizio in vigore
quella settimana. Restano da scegliere solo le assenze (ferie, malattia,
permessi) e il riposo compensativo.

### Variazioni di orario

- **Continuativa**: cambia l'orario di servizio da quella settimana in poi,
  fino a un'altra variazione continuativa. Non ha una data di fine.
- **Temporanea**: vale solo per le settimane indicate (anche una sola);
  finite quelle, torna in vigore l'orario precedente.

L'orario di inizio anno è la base: non scade mai ed è quello a cui si torna.

Le 36 ore settimanali sono **24h di presenza + 12h di studio**, e si controllano
separatamente: la presenza non può superare le 24h. Le ore in più si pianificano
nella fascia Straordinario (fino a 9h) o Masterclass, che stanno fuori dalle 36h
ma dentro il tetto delle 45h.

### Come si contano le ore di una giornata

1. Si guarda **quali fasce sono state toccate** dalle timbrature (il confine fra
   una fascia e l'altra sta a metà strada). Le fasce in cui non si è timbrato
   affatto restano fuori: chi viene solo per la Masterclass del pomeriggio non
   riempie l'ordinario del mattino, che risulta mancante.
2. Le ore timbrate **riempiono le fasce toccate nell'ordine in cui stanno in
   orario**, ciascuna fino alla propria durata. Si confrontano le **durate**,
   non gli orari esatti: entrare in ritardo fa slittare tutto, e lo
   straordinario scatta solo quando l'ordinario è completo.
   - fascia 9:00–14:00, timbro 9:13–14:13 → 5h00 contate, nessuno scarto
   - fascia 9:00–14:00, timbro 8:58–14:06 → 5h00 contate, 8 minuti fuori orario
   - fascia 9:00–14:00, timbro 9:05–13:50 → 4h45 contate, 15 minuti mancanti
   - ordinario 8:00–12:00 + straordinario 12:00–14:00, timbro 8:10–14:05 →
     4h00 di ordinario e 1h55 di straordinario: niente mancante, niente fuori
     orario
3. Se la fascia prevede una pausa e la pausa non è stata timbrata, la pausa si
   sottrae dalle ore timbrate di quella fascia, ma solo per la parte che supera
   le **7h12 di lavoro effettivo**, la soglia oltre la quale la pausa scatta per
   legge: chi timbra 7h non deve nessuna pausa. Il riposo compensativo non è
   lavoro e non fa scattare la pausa, anche se porta il totale del giorno oltre
   le 7h12.
   - fascia 9:00–17:30 con 30' di pausa, timbro 9:15–16:15 (7h) + 1h di riposo
     compensativo → 7h contate + 1h = 8h00, nessuna pausa tolta
   - stessa fascia, timbro 9:00–17:30 (8h30) → 30' tolti, 8h00 contate
4. **Nessuna tolleranza**, né in più né in meno.
5. Le ore mancanti fanno debito e generano un avviso.
6. Le ore in più, o timbrate fuori da ogni fascia, non contano: restano
   registrate, visibili, e segnalate come «da autorizzare». Se le autorizzo
   diventano straordinario.
7. Le timbrature restano sempre visibili come sono state fatte.

## 3. Straordinario ordinario

- Pianificato in Orario: già autorizzato, nessun avviso.
- Non pianificato: avviso «chiedi l'autorizzazione». Autorizzandolo dopo,
  diventa straordinario a tutti gli effetti.
- **Non è mai pagato.** Va a credito, e il credito serve a coprire un debito o
  a prendere un riposo compensativo.
- Massimo 9 ore a settimana.

## 4. Masterclass

- Si pianifica in Orario (fascia viola).
- Quota annua: **40 ore per anno accademico**.
  - le **prime 20 ore** dell'anno sono **pagate a parte**: non entrano nel saldo;
  - le **successive 20 ore** vanno **a credito**, come lo straordinario ordinario.
  - il conteggio è automatico e in ordine di data.
- Oltre le 40 ore: avviso, serve l'autorizzazione della Direzione amministrativa.
  Le ore restano registrate ma non compensate finché non le autorizzo.
- **Erosione**: se in una settimana la Masterclass supera le 9 ore, l'eccedenza
  riduce le ore ordinarie che si possono fare, perché il tetto delle 45 ore non
  si supera. L'obbligo però resta di 24 ore, quindi le ore ordinarie non fatte
  **diventano debito da recuperare**.
  Esempio: 21h ordinarie + 12h studio + 12h Masterclass = 45h, debito 3h.
- Tutte le ore di Masterclass contano nella quota annua, comprese quelle che
  hanno eroso l'ordinario.

## 5. Debito, credito, riposo compensativo

- **Debito**: settimana sotto le 24 ore di presenza ordinaria, per ore mancanti,
  erosione da Masterclass o permesso breve.
- **Credito**: straordinario ordinario autorizzato, più le ore di Masterclass
  oltre le prime 20 dell'anno. Un unico saldo, ma ogni quota ricorda la propria
  origine (ordinario o Masterclass) per i moduli e i riepiloghi.
- Il credito copre un debito esistente oppure finanzia un riposo compensativo.
  L'abbinamento è automatico e parte dal debito più vecchio, ma si può indicare
  **quale** debito lo straordinario recupera (campo «Recupera»):
  - in **Orario di lavoro**, sotto la fascia di straordinario del giorno: vale
    per tutte le settimane del periodo e finisce nella *Comunicazione
    dell'orario di servizio*, che si manda in anticipo alla segreteria;
  - nel **giorno** in Timbrature, per correggere un caso singolo: se non si
    tocca, vale quello dell'orario.
  La scelta viene servita per prima, il resto segue l'ordine automatico. Il
  prospetto presenze lo stampa giorno per giorno, con la dicitura «(indicato)»
  sugli abbinamenti scelti.
  Se più giorni della stessa settimana puntano allo stesso debito, le ore si
  **scalano in ordine di giorno**: il primo ne copre una parte, i successivi il
  residuo, e l'eccedenza resta a credito. La Comunicazione dell'orario di
  servizio scrive per ogni giornata quante ore vanno sul debito e quante ne
  restano da recuperare dopo.
- **Riposo compensativo**: sempre collegato a una richiesta autorizzata (dall'app
  o cartacea). Le ore si prendono **dalle più vecchie alle più recenti**, e il
  modulo si compila da solo con quei giorni. Nella settimana del riposo le ore
  coperte contano come presenza, marcate come riposo compensativo, così la
  settimana risulta in pari.
- Il credito **scade il 31 ottobre**, fine dell'anno accademico.

## 6. Permesso breve

Uscita anticipata autorizzata con modulo: le ore non fatte vanno a debito e si
recuperano in seguito. Modulo ufficiale da acquisire.

## 7. Avvisi che l'app deve dare

- ore mancanti rispetto alle fasce previste;
- ore timbrate fuori orario o oltre la fascia, da autorizzare;
- straordinario ordinario oltre le 9 ore settimanali;
- settimana oltre le 45 ore complessive (limite di legge);
- Masterclass oltre le 40 ore annue;
- credito in scadenza al 31 ottobre.

## 8. Cosa sparisce rispetto a prima

- la domanda settimanale «straordinario a credito o pagato»: l'ordinario non è
  mai pagato, quindi va sempre a credito;
- la domanda settimanale sulle Masterclass «pagate o a recupero»: decide la
  quota annua 20 + 20;
- la domanda sulle Masterclass oltre il tetto delle 9 ore: l'erosione è
  automatica e il debito nasce da sé.

## 9. Decisioni operative

- Nessuna tolleranza: entrare tardi e uscire tardi della stessa misura e' una
  giornata piena, perche' si confrontano le durate.
- La pausa prevista si sottrae solo se non e' stata timbrata, e solo per la
  parte di lavoro effettivo oltre le 7h12: non si scende mai sotto quella
  soglia togliendo la pausa.
- Le ore autorizzate a posteriori si indicano nel giorno, in minuti, anche solo
  in parte: chiesti 30 minuti, fatti 35, se ne autorizzano 30.
- Le ore autorizzate prendono il tipo dell'ultima fascia della giornata: dopo
  una Masterclass restano Masterclass, altrimenti sono straordinario ordinario.
- Straordinario ordinario oltre le 9 ore settimanali: si segnala, ma se e'
  autorizzato va comunque a credito.
- Il credito scade il 31 ottobre: per ora la chiusura d'anno riporta il saldo
  come prima e non azzera nulla, in attesa di conferma.
- Una settimana senza nessuna timbratura non entra nel saldo: l'app non puo'
  sapere se sono ore dimenticate o una settimana non lavorativa. Viene
  segnalata («Non conteggiata», elenco in Riepilogo) finche' non si compila
  oppure non si rimuove con «Rimuovi settimana».
