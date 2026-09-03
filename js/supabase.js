/* ============================================================================
   Init del client Supabase (spec sez. 3).
   Qui vanno SOLO le credenziali pubbliche: Project URL + Publishable key.
   La Secret key (sb_secret_...) NON deve MAI comparire in questo repo.
   ========================================================================== */
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ▼▼ INCOLLA QUI I VALORI DA: Dashboard → Settings → API Keys ▼▼
const SUPABASE_URL = 'https://jvibhznecyloendjmazt.supabase.co';
const SUPABASE_KEY = 'sb_publishable_EFI5bE5Y__JATvhnmVguKg_R-dBDreJ';
// ▲▲ ------------------------------------------------------------- ▲▲

/* keepalive: le richieste piccole (i salvataggi) sopravvivono alla chiusura
   della pagina; il limite del browser per keepalive e' 64KB di corpo. */
const fetchKeepalive = (input, init = {}) => {
  const corpo = init.body;
  const piccolo = !corpo || (typeof corpo === 'string' && corpo.length < 60000);
  return fetch(input, piccolo ? { ...init, keepalive: true } : init);
};
export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  global: { fetch: fetchKeepalive },
});

export function configurata() {
  return !SUPABASE_URL.startsWith('INCOLLA') && !SUPABASE_KEY.startsWith('INCOLLA');
}
