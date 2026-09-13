-- ============================================================================
-- Registro presenze — Straordinario autorizzato a posteriori (dopo 01..12)
-- timbrature.straord_aut_min : minuti timbrati fuori dalle fasce previste che
--   sono stati autorizzati come straordinario per quel giorno.
--   null = nessuna autorizzazione.
-- ============================================================================

alter table public.timbrature add column if not exists straord_aut_min int;
