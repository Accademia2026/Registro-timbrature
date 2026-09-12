-- ============================================================================
-- Registro presenze — Masterclass pagate a parte (dopo 01..11)
-- autorizzazioni.mc_pagate_min : minuti di Masterclass della settimana pagati
--   a parte; con mc_credito_min (a recupero) il resto delle ore di Masterclass
--   risulta straordinario non autorizzato. null = non ancora deciso
-- ============================================================================

alter table public.autorizzazioni add column if not exists mc_pagate_min int;
