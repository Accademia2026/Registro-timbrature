-- ============================================================================
-- Registro presenze — Esito deciso della settimana (dopo 01..15)
-- autorizzazioni.esito_min : credito (+) o debito (-) della settimana, in minuti,
--   deciso a mano. Quando c'e', sostituisce il calcolo dalle fasce: serve per le
--   settimane verificate una per una. null = l'app calcola da sola.
-- autorizzazioni.ecc_ok : risposta alla domanda "le ore in piu' non previste
--   dall'Orario contano?"  true = si', a credito · false = no · null = da chiedere
-- ============================================================================

alter table public.autorizzazioni add column if not exists esito_min int;
alter table public.autorizzazioni add column if not exists ecc_ok boolean;
