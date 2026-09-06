-- ============================================================================
-- Registro presenze — Masterclass oltre il tetto delle 9h (dopo 01..04)
-- autorizzazioni.mc_oltre_min : minuti di Masterclass oltre il tetto
--                               settimanale autorizzati (0 = "no": come mai
--                               fatti; null = domanda non ancora risposta)
-- autorizzazioni.minuti        : diventa nullable, null = nessuna risposta
--                               sullo straordinario ordinario
-- ============================================================================

alter table public.autorizzazioni alter column minuti drop not null;
alter table public.autorizzazioni add column if not exists mc_oltre_min int;
