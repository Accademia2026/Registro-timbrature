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

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

export function configurata() {
  return !SUPABASE_URL.startsWith('INCOLLA') && !SUPABASE_KEY.startsWith('INCOLLA');
}
