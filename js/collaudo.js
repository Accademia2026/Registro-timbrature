/* ============================================================================
   Collaudo del data layer: giro completo scrittura → lettura → pulizia su
   date fittizie (1999), più un tentativo di violazione RLS che DEVE fallire.
   Si lancia dal pulsante in index.html, da loggati. Non tocca i dati veri.
   ========================================================================== */
import { supabase } from './supabase.js';
import * as repo from './repo.js';

const DATA_TEST = '1999-01-04';   // lunedì remoto: mai usato dai dati veri

export async function collaudo() {
  const esiti = [];
  const punto = (nome, ok, dettagli = '') => esiti.push({ nome, ok, dettagli });

  /* 1 — loadAll ricompone DB */
  try {
    const DB = await repo.loadAll();
    punto('loadAll', !!DB && Array.isArray(DB.entitlements),
      `${Object.keys(DB.entries).length} giorni, ${DB.entitlements.length} diritti, ` +
      `${DB.people.length} persone, ${DB.events.length} eventi`);
  } catch (e) { punto('loadAll', false, e.message); }

  /* 2 — timbratura: upsert → rilettura → delete */
  try {
    repo.saveGiorno(DATA_TEST, { act: 'presenza', m1in: '08:00', m1out: '14:00', note: 'collaudo' }, false);
    await repo.flush();
    const { data } = await supabase.from('timbrature').select('*').eq('data', DATA_TEST).maybeSingle();
    const ok = data && data.attivita === 'presenza' && String(data.m1in).startsWith('08:00');
    repo.saveGiorno(DATA_TEST, null, false);           // vuota → delete
    await repo.flush();
    const { data: dopo } = await supabase.from('timbrature').select('id').eq('data', DATA_TEST).maybeSingle();
    punto('timbratura upsert/rilettura/delete', !!ok && !dopo);
  } catch (e) { punto('timbratura upsert/rilettura/delete', false, e.message); }

  /* 3 — autorizzazione settimanale: upsert → delete */
  try {
    repo.saveAutorizzazione(DATA_TEST, 30);
    await repo.flush();
    const { data } = await supabase.from('autorizzazioni').select('minuti').eq('settimana', DATA_TEST).maybeSingle();
    repo.saveAutorizzazione(DATA_TEST, null);
    await repo.flush();
    punto('autorizzazione upsert/delete', data?.minuti === 30);
  } catch (e) { punto('autorizzazione upsert/delete', false, e.message); }

  /* 4 — persona + evento collegato, poi pulizia */
  try {
    const pid = await repo.insertPersona({ name: '__collaudo__', role: 'docente', color: '#000000' });
    const eid = await repo.insertEvento({ personId: pid, date: DATA_TEST, start: '10:00', end: '11:00', mode: 'single' });
    await repo.deleteEvento(eid);
    await repo.deletePersona(pid);
    punto('persona + evento (insert/delete)', Number.isFinite(pid) && Number.isFinite(eid));
  } catch (e) { punto('persona + evento (insert/delete)', false, e.message); }

  /* 5 — RLS: insert con user_id di un ALTRO deve essere rifiutato */
  try {
    const { error } = await supabase.from('timbrature').insert({
      user_id: '00000000-0000-0000-0000-000000000001', data: '1999-01-05',
    });
    punto('RLS: user_id falsificato rifiutato', !!error, error ? error.message : 'ACCETTATO: PROBLEMA!');
    if (!error) await supabase.from('timbrature').delete().eq('data', '1999-01-05');
  } catch (e) { punto('RLS: user_id falsificato rifiutato', true, e.message); }

  return esiti;
}
