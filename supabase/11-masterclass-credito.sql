-- ============================================================================
-- Registro presenze — Masterclass a credito (dopo 01..10)
-- autorizzazioni.mc_credito_min : minuti di Masterclass della settimana messi
--   a credito nel saldo invece che pagati a parte; null = non ancora deciso
-- ============================================================================

alter table public.autorizzazioni add column if not exists mc_credito_min int;
