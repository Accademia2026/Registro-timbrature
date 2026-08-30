/* ============================================================================
   Data layer (spec sez. 6): sostituisce Store/localStorage con Supabase.
   - loadAll() ricompone l'oggetto DB nella STESSA forma del prototipo:
     viste e funzioni di calcolo non si accorgono della differenza.
   - Salvataggi mirati per entità (upsert/delete sulla riga toccata),
     con debounce per non scrivere a ogni battuta.
   user_id non viene mai inviato: lo mette il DB (default auth.uid()) e la
   RLS garantisce che ogni utente tocchi solo le proprie righe.
   ========================================================================== */
import { supabase } from './supabase.js';

/* ---- helpers ---- */
const pad = (n) => String(n).padStart(2, '0');
const t2m = (t) => {
  if (!t) return null;
  const m = /^(\d{1,2}):(\d{2})/.exec(String(t).trim());
  if (!m) return null;
  const h = +m[1], mi = +m[2];
  return (h > 23 || mi > 59) ? null : h * 60 + mi;
};
const hm = (v) => (v ? String(v).slice(0, 5) : undefined);   // '08:30:00' → '08:30'
const orNull = (v) => (v === '' || v === undefined ? null : v);

/** Ricalcola schedule (minuti d'obbligo per giorno) dagli slots — stessa
    formula del prototipo: fine − inizio − pausa. */
function scheduleFromSlots(slots) {
  const schedule = {};
  for (const wd of [1, 2, 3, 4, 5, 6, 0]) {
    const sl = (slots && slots[wd]) || {};
    const ds = t2m(sl.start), de = t2m(sl.end);
    schedule[wd] = (ds != null && de != null && de > ds) ? Math.max(0, (de - ds) - (sl.pausa || 0)) : 0;
  }
  return schedule;
}

const periodoVuoto = () => ({
  from: '',
  schedule: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 0: 0 },
  slots: { 1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 0: {} },
});

/* id utente corrente (lettura locale della sessione, una volta sola) */
let _uid = null;
async function uid() {
  if (!_uid) {
    const { data } = await supabase.auth.getSession();
    _uid = data?.session?.user?.id ?? null;
  }
  return _uid;
}

/* Gestione errori: chi innesta il repo può farsi avvisare (es. toast). */
let onError = (contesto, error) => console.error('[repo]', contesto, error);
export function setOnError(fn) { onError = fn; }
function check(contesto, { error, data } = {}) {
  if (error) { onError(contesto, error); throw error; }
  return data;
}

/* ============================================================ loadAll */
export async function loadAll() {
  const [imp, tim, per, dir, aut, ppl, evt] = await Promise.all([
    supabase.from('impostazioni').select('*').maybeSingle(),
    supabase.from('timbrature').select('*'),
    supabase.from('periodi').select('*').order('valido_dal', { ascending: true, nullsFirst: true }),
    supabase.from('diritti_permessi').select('*').order('ordine'),
    supabase.from('autorizzazioni').select('*'),
    supabase.from('persone').select('*').order('id'),
    supabase.from('eventi').select('*').order('id'),
  ]);

  const impostazioni = check('caricamento impostazioni', imp) || {};
  const timbrature   = check('caricamento timbrature', tim) || [];
  const periodi      = check('caricamento periodi', per) || [];
  const diritti      = check('caricamento diritti', dir) || [];
  const autorizz     = check('caricamento autorizzazioni', aut) || [];
  const persone      = check('caricamento persone', ppl) || [];
  const eventi       = check('caricamento eventi', evt) || [];

  /* entries + skipDays dalla stessa tabella */
  const entries = {}, skipDays = {};
  for (const r of timbrature) {
    if (r.rimosso) skipDays[r.data] = true;
    const e = {};
    if (r.attivita) e.act = r.attivita;
    if (r.m1in) e.m1in = hm(r.m1in);
    if (r.m1out) e.m1out = hm(r.m1out);
    if (r.m2in) e.m2in = hm(r.m2in);
    if (r.m2out) e.m2out = hm(r.m2out);
    if (r.permesso_min != null) e.ph = r.permesso_min;
    if (r.studio_min != null) e.studyMin = r.studio_min;
    if (r.nota) e.note = r.nota;
    if (Object.keys(e).length) entries[r.data] = e;
  }

  const mapPeriodi = (tipo) => {
    const list = periodi.filter((r) => r.tipo === tipo).map((r) => ({
      from: r.valido_dal || '',
      slots: r.slots || {},
      schedule: scheduleFromSlots(r.slots),
    }));
    return list.length ? list : [periodoVuoto()];
  };

  const authorized = {};
  for (const r of autorizz) authorized[r.settimana] = r.minuti;

  return {
    startDate: impostazioni.data_inizio_aa || '',
    yearLabel: impostazioni.anno_label || '',
    initialBalanceMin: impostazioni.saldo_iniziale_min || 0,
    schedulePeriods: mapPeriodi('presenza'),
    studyPeriods: mapPeriodi('studio'),
    entitlements: diritti.map((r) => ({
      id: r.tipo,
      label: r.etichetta || r.tipo,
      unit: r.unita === 'gg' ? 'GG' : 'ORE',
      total: +r.totale,
      used0: +r.gia_fruito,
    })),
    entries,
    skipDays,
    authorized,
    diary: {},
    /* id come STRINGHE: il prototipo li confronta con === contro i dataset
       del DOM (sempre stringhe). PostgREST accetta stringhe numeriche. */
    people: persone.map((r) => ({
      id: String(r.id),
      name: r.nome,
      role: r.ruolo,
      color: r.colore,
      ...(r.docente_id != null ? { teacherId: String(r.docente_id) } : {}),
    })),
    events: eventi.map((r) => ({
      id: String(r.id),
      personId: r.persona_id != null ? String(r.persona_id) : null,
      date: r.data,
      start: hm(r.ora_inizio),
      end: hm(r.ora_fine),
      mode: r.ripetizione === 'weekly' ? 'weekly' : 'single',
      until: r.fino_al || null,
      notify: r.avviso_min,
      note: r.nota || '',
      countTeacher: !!r.conta_docente,
    })),
  };
}

/* ============================================================ debounce */
const pendenti = new Map();               // chiave → { timer, fn }
function debounced(chiave, fn, ms = 500) {
  const prev = pendenti.get(chiave);
  if (prev) clearTimeout(prev.timer);
  pendenti.set(chiave, { fn, timer: setTimeout(() => { pendenti.delete(chiave); fn(); }, ms) });
}
/** Scrive subito tutto ciò che è in coda (da chiamare su logout/chiusura). */
export function flush() {
  const daFare = [...pendenti.values()];
  for (const p of daFare) clearTimeout(p.timer);
  pendenti.clear();
  return Promise.allSettled(daFare.map((p) => p.fn()));
}

/* ============================================================ salvataggi */

/** Impostazioni globali (debounced). */
export function saveImpostazioni(DB) {
  debounced('impostazioni', async () => {
    const { error } = await supabase.from('impostazioni').update({
      data_inizio_aa: orNull(DB.startDate),
      anno_label: orNull(DB.yearLabel),
      saldo_iniziale_min: DB.initialBalanceMin || 0,
    }).eq('user_id', await uid());
    if (error) onError('salvataggio impostazioni', { error });
  });
}

/** Il giorno `dateISO`: upsert di entry + flag rimosso, o delete se vuoto. */
export function saveGiorno(dateISO, entry, rimosso) {
  debounced('giorno:' + dateISO, async () => {
    const e = entry || {};
    const vuota = !e.act && !e.m1in && !e.m1out && !e.m2in && !e.m2out
      && e.ph == null && (e.studyMin == null || e.studyMin === 0) && !e.note;
    if (vuota && !rimosso) {
      const { error } = await supabase.from('timbrature').delete().eq('data', dateISO);
      if (error) onError('cancellazione giorno', { error });
      return;
    }
    const { error } = await supabase.from('timbrature').upsert({
      data: dateISO,
      attivita: orNull(e.act),
      m1in: orNull(e.m1in), m1out: orNull(e.m1out),
      m2in: orNull(e.m2in), m2out: orNull(e.m2out),
      permesso_min: e.ph ?? null,
      studio_min: e.studyMin ?? null,
      nota: orNull(e.note),
      rimosso: !!rimosso,
    }, { onConflict: 'user_id,data' });
    if (error) onError('salvataggio giorno', { error });
  });
}

/** Orari a periodi: sostituisce tutte le righe del tipo (poche righe). */
export function savePeriodi(tipo, lista) {
  debounced('periodi:' + tipo, async () => {
    const del = await supabase.from('periodi').delete().eq('tipo', tipo);
    if (del.error) return onError('salvataggio periodi', del);
    const rows = lista.map((p) => ({ tipo, valido_dal: orNull(p.from), slots: p.slots || {} }));
    if (rows.length) {
      const ins = await supabase.from('periodi').insert(rows);
      if (ins.error) onError('salvataggio periodi', ins);
    }
  });
}

/** Diritti/limiti permessi: sostituisce l'elenco intero (≈14 righe). */
export function saveDiritti(entitlements) {
  debounced('diritti', async () => {
    const del = await supabase.from('diritti_permessi').delete().eq('user_id', await uid());
    if (del.error) return onError('salvataggio diritti', del);
    const rows = entitlements.map((e, i) => ({
      tipo: e.id,
      etichetta: e.label,
      unita: e.unit === 'GG' ? 'gg' : 'ore',
      totale: e.total || 0,
      gia_fruito: e.used0 || 0,
      ordine: i,
    }));
    if (rows.length) {
      const ins = await supabase.from('diritti_permessi').insert(rows);
      if (ins.error) onError('salvataggio diritti', ins);
    }
  });
}

/** Eccedenza autorizzata della settimana (minuti null/undefined = rimuovi). */
export function saveAutorizzazione(lunediISO, minuti) {
  debounced('aut:' + lunediISO, async () => {
    if (minuti == null) {
      const { error } = await supabase.from('autorizzazioni').delete().eq('settimana', lunediISO);
      if (error) onError('rimozione autorizzazione', { error });
    } else {
      const { error } = await supabase.from('autorizzazioni').upsert(
        { settimana: lunediISO, minuti },
        { onConflict: 'user_id,settimana' });
      if (error) onError('salvataggio autorizzazione', { error });
    }
  });
}

/* ---- persone ed eventi: id generati dal DB, quindi niente debounce:
       l'id serve subito al chiamante. ---- */

export async function insertPersona(p) {
  const r = await supabase.from('persone').insert({
    nome: p.name, ruolo: p.role, colore: p.color || null,
    docente_id: p.teacherId ?? null,
  }).select('id').single();
  return String(check('creazione persona', r).id);
}
export async function updatePersona(id, p) {
  check('modifica persona', await supabase.from('persone').update({
    nome: p.name, ruolo: p.role, colore: p.color || null,
    docente_id: p.teacherId ?? null,
  }).eq('id', id));
}
export async function deletePersona(id) {
  check('eliminazione persona', await supabase.from('persone').delete().eq('id', id));
}

/** Azzera solo le giornate: timbrature (entries+skipDays) e autorizzazioni. */
export async function clearTimbrature() {
  const u = await uid();
  check('azzeramento timbrature', await supabase.from('timbrature').delete().eq('user_id', u));
  check('azzeramento autorizzazioni', await supabase.from('autorizzazioni').delete().eq('user_id', u));
}

/** Sostituisce TUTTI i dati dell'utente con l'oggetto DB dato (import backup /
    azzera tutto). Le persone possono avere id vecchi (stringhe uid del
    prototipo): vengono reinserite e gli eventi rimappati sui nuovi id. */
export async function replaceAll(DB) {
  const u = await uid();
  // ordine: prima gli eventi (referenziano persone), poi il resto
  check('pulizia eventi', await supabase.from('eventi').delete().eq('user_id', u));
  check('pulizia persone', await supabase.from('persone').delete().eq('user_id', u));
  check('pulizia timbrature', await supabase.from('timbrature').delete().eq('user_id', u));
  check('pulizia periodi', await supabase.from('periodi').delete().eq('user_id', u));
  check('pulizia diritti', await supabase.from('diritti_permessi').delete().eq('user_id', u));
  check('pulizia autorizzazioni', await supabase.from('autorizzazioni').delete().eq('user_id', u));

  check('import impostazioni', await supabase.from('impostazioni').update({
    data_inizio_aa: orNull(DB.startDate),
    anno_label: orNull(DB.yearLabel),
    saldo_iniziale_min: DB.initialBalanceMin || 0,
  }).eq('user_id', u));

  const giorni = new Set([...Object.keys(DB.entries || {}), ...Object.keys(DB.skipDays || {})]);
  const timRows = [...giorni].map((d) => {
    const e = (DB.entries || {})[d] || {};
    return {
      data: d,
      attivita: orNull(e.act),
      m1in: orNull(e.m1in), m1out: orNull(e.m1out),
      m2in: orNull(e.m2in), m2out: orNull(e.m2out),
      permesso_min: e.ph ?? null,
      studio_min: e.studyMin ?? null,
      nota: orNull(e.note),
      rimosso: !!(DB.skipDays || {})[d],
    };
  });
  if (timRows.length) check('import timbrature', await supabase.from('timbrature').insert(timRows));

  const perRows = [
    ...(DB.schedulePeriods || []).map((p) => ({ tipo: 'presenza', valido_dal: orNull(p.from), slots: p.slots || {} })),
    ...(DB.studyPeriods || []).map((p) => ({ tipo: 'studio', valido_dal: orNull(p.from), slots: p.slots || {} })),
  ];
  if (perRows.length) check('import periodi', await supabase.from('periodi').insert(perRows));

  const dirRows = (DB.entitlements || []).map((e, i) => ({
    tipo: e.id, etichetta: e.label,
    unita: e.unit === 'GG' ? 'gg' : 'ore',
    totale: e.total || 0, gia_fruito: e.used0 || 0, ordine: i,
  }));
  if (dirRows.length) check('import diritti', await supabase.from('diritti_permessi').insert(dirRows));

  const autRows = Object.entries(DB.authorized || {}).map(([settimana, minuti]) => ({ settimana, minuti }));
  if (autRows.length) check('import autorizzazioni', await supabase.from('autorizzazioni').insert(autRows));

  // persone: inserite una a una per ottenere i nuovi id e rimappare
  const idMap = new Map();
  for (const p of DB.people || []) {
    const r = await supabase.from('persone').insert({
      nome: p.name, ruolo: p.role, colore: p.color || null,
    }).select('id').single();
    idMap.set(p.id, check('import persona', r).id);
  }
  for (const p of DB.people || []) {           // secondo giro: associazioni docente
    if (p.teacherId != null && idMap.has(p.teacherId)) {
      check('import associazione docente', await supabase.from('persone')
        .update({ docente_id: idMap.get(p.teacherId) }).eq('id', idMap.get(p.id)));
    }
  }
  const evtRows = (DB.events || []).map((ev) => ({
    ...evtRow(ev),
    persona_id: ev.personId != null ? (idMap.get(ev.personId) ?? null) : null,
  }));
  if (evtRows.length) check('import eventi', await supabase.from('eventi').insert(evtRows));
}

const evtRow = (ev) => ({
  persona_id: ev.personId ?? null,
  data: ev.date,
  ora_inizio: ev.start,
  ora_fine: ev.end,
  ripetizione: ev.mode === 'weekly' ? 'weekly' : null,
  fino_al: orNull(ev.until),
  avviso_min: ev.notify ?? null,
  conta_docente: !!ev.countTeacher,
  nota: orNull(ev.note),
});
export async function insertEvento(ev) {
  const r = await supabase.from('eventi').insert(evtRow(ev)).select('id').single();
  return String(check('creazione attività', r).id);
}
export async function updateEvento(id, ev) {
  check('modifica attività', await supabase.from('eventi').update(evtRow(ev)).eq('id', id));
}
export async function deleteEvento(id) {
  check('eliminazione attività', await supabase.from('eventi').delete().eq('id', id));
}
