/* ============================================================================
   Autenticazione (spec sez. 5): login, logout, reset password.
   Nessuna registrazione: gli account nascono solo su invito dalla dashboard.
   ========================================================================== */
import { supabase } from './supabase.js';

const ERRORI = {
  'Invalid login credentials': 'Email o password errati.',
  'Email not confirmed': 'Email non ancora confermata: controlla la casella di posta.',
  'For security purposes, you can only request this once every 60 seconds':
    'Per sicurezza puoi richiederlo una sola volta al minuto: riprova tra poco.',
};
export function msgErrore(error) {
  return ERRORI[error?.message] || 'Errore: ' + (error?.message || 'imprevisto');
}

export async function login(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  return { user: data?.user ?? null, error };
}

export async function logout() {
  await supabase.auth.signOut();
}

/** Invia la mail di reset; il link riporta alla pagina imposta-password. */
export async function resetPassword(email) {
  const redirectTo = new URL('imposta-password.html', location.href).href;
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  return { error };
}

/** Sessione corrente (null se non loggato). */
export async function sessione() {
  const { data } = await supabase.auth.getSession();
  return data?.session ?? null;
}

/** Imposta la password dell'utente della sessione corrente (invito o reset). */
export async function impostaPassword(password) {
  const { error } = await supabase.auth.updateUser({ password });
  return { error };
}
