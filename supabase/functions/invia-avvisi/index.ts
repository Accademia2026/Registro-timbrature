// ============================================================================
// Registro presenze — Edge Function "invia-avvisi"
// Chiamata ogni minuto dal pianificatore (Cron) di Supabase: per ogni attività
// del calendario con un avviso impostato, quando arriva il momento spedisce
// una notifica push a tutti i dispositivi iscritti dell'utente.
// Chiamata dall'app con { test: true }: manda una notifica di prova.
//
// Segreti da impostare (Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (es. mailto:admin@weega.it),
//   CRON_SECRET (una parola d'ordine a piacere, la stessa messa nel Cron),
//   SB_SECRET_KEY (la "secret key" del progetto: Settings → API Keys)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sono forniti da Supabase.
// ============================================================================
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const URL_DB = Deno.env.get('SUPABASE_URL')!;
/* chiave con pieni poteri: la 'secret key' nuova (SB_SECRET_KEY, da mettere nei Secrets)
   oppure quella storica che Supabase fornisce da solo */
const CHIAVE_SERVIZIO = Deno.env.get('SB_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const VAPID_PUB = Deno.env.get('VAPID_PUBLIC_KEY') || '';
const VAPID_PRIV = Deno.env.get('VAPID_PRIVATE_KEY') || '';
const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@weega.it';
const CRON_SECRET = Deno.env.get('CRON_SECRET') || '';

const db = createClient(URL_DB, CHIAVE_SERVIZIO, { auth: { persistSession: false } });
if (VAPID_PUB && VAPID_PRIV) webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUB, VAPID_PRIV);

/* CORS: l'app nel browser chiama la funzione per la notifica di prova */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json' } });

/* data e ora attuali in Italia (Europe/Rome), indipendenti dal server */
function adessoRoma() {
  const parti = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Rome', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', weekday: 'short', hour12: false,
  }).formatToParts(new Date());
  const g = (t: string) => parti.find((p) => p.type === t)?.value || '';
  const giorno = `${g('year')}-${g('month')}-${g('day')}`;
  const minuti = parseInt(g('hour'), 10) % 24 * 60 + parseInt(g('minute'), 10);
  const wd = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[g('weekday') as 'Sun'] ?? 0;
  return { giorno, minuti, wd };
}
const t2m = (t: string) => { const [h, m] = String(t).split(':').map(Number); return h * 60 + m; };
const wdDi = (iso: string) => new Date(iso + 'T12:00:00Z').getUTCDay();

type Iscrizione = { id: number; user_id: string; endpoint: string; p256dh: string; auth: string };

/* spedisce a tutti i dispositivi dell'utente; elimina le iscrizioni morte */
async function spedisci(iscrizioni: Iscrizione[], payload: Record<string, unknown>) {
  let ok = 0;
  for (const s of iscrizioni) {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify(payload), { TTL: 600 },
      );
      ok++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await db.from('push_subscriptions').delete().eq('id', s.id);
      else console.error('push fallita', s.id, code, (e as Error).message);
    }
  }
  return ok;
}

Deno.serve(async (req) => {
  try { return await gestisci(req); }
  catch (e) {
    /* qualunque imprevisto finisce nei Logs e nella risposta, mai un 500 muto */
    const msg = (e as Error)?.message || String(e);
    console.error('invia-avvisi: errore', msg, (e as Error)?.stack);
    return json({ errore: msg }, 500);
  }
});

async function gestisci(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (!VAPID_PUB || !VAPID_PRIV) return json({ errore: 'chiavi VAPID mancanti' }, 500);
  if (!CHIAVE_SERVIZIO) return json({ errore: 'SB_SECRET_KEY mancante' }, 500);
  let body: { test?: boolean } = {};
  try { body = await req.json(); } catch (_) { /* nessun corpo: chiamata pianificata */ }

  /* ---- notifica di prova richiesta dall'app (con il token dell'utente) ---- */
  if (body.test) {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: u } = await db.auth.getUser(jwt);
    if (!u?.user) return json({ errore: 'non autenticato' }, 401);
    const { data: iscr } = await db.from('push_subscriptions').select('*').eq('user_id', u.user.id);
    const n = await spedisci((iscr || []) as Iscrizione[], {
      title: 'Registro presenze', body: 'Le notifiche funzionano su questo dispositivo ✔', tag: 'prova',
    });
    return json({ inviate: n, dispositivi: (iscr || []).length });
  }

  /* ---- chiamata pianificata: solo con la parola d'ordine o la chiave di servizio ---- */
  const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const segreto = req.headers.get('x-cron-secret') || '';
  if (!((CRON_SECRET && segreto === CRON_SECRET) || bearer === CHIAVE_SERVIZIO)) {
    return json({ errore: 'non autorizzato' }, 401);
  }

  const { giorno, minuti, wd } = adessoRoma();
  const { data: eventi, error } = await db.from('eventi')
    .select('id,user_id,data,ora_inizio,ora_fine,tipo,persona_id,ripetizione,fino_al,avviso_min')
    .not('avviso_min', 'is', null)
    .or(`data.eq.${giorno},and(ripetizione.eq.weekly,data.lte.${giorno})`);
  if (error) return json({ errore: error.message }, 500);

  const daAvvisare = (eventi || []).filter((ev) => {
    if (ev.ripetizione === 'weekly') {
      if (wdDi(ev.data) !== wd) return false;
      if (ev.fino_al && ev.fino_al < giorno) return false;
    } else if (ev.data !== giorno) return false;
    const scatto = t2m(ev.ora_inizio) - (ev.avviso_min || 0);
    /* finestra di 3 minuti: tollera i ritardi del pianificatore */
    return scatto <= minuti && scatto > minuti - 3;
  });

  let inviate = 0;
  for (const ev of daAvvisare) {
    /* memoria degli avvisi: se la riga esiste già, questo avviso è già partito */
    const ins = await db.from('avvisi_inviati').insert({ user_id: ev.user_id, evento_id: ev.id, giorno });
    if (ins.error) continue;                       // duplicato (unique) o altro: si salta
    const { data: iscr } = await db.from('push_subscriptions').select('*').eq('user_id', ev.user_id);
    if (!iscr || !iscr.length) continue;
    let nome = ev.tipo || 'Attività';
    if (ev.persona_id != null) {
      const { data: p } = await db.from('persone').select('nome').eq('id', ev.persona_id).maybeSingle();
      if (p?.nome) nome = p.nome;
    }
    const orario = `${String(ev.ora_inizio).slice(0, 5)}–${String(ev.ora_fine).slice(0, 5)}`;
    inviate += await spedisci(iscr as Iscrizione[], {
      title: 'Attività in arrivo', body: `${nome} · ${orario}`, tag: 'evento-' + ev.id, url: './',
    });
  }
  return json({ ora: `${giorno} ${Math.floor(minuti / 60)}:${String(minuti % 60).padStart(2, '0')}`, candidati: daAvvisare.length, inviate });
}
