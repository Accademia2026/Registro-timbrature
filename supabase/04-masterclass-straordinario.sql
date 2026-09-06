-- ============================================================================
-- Registro presenze — Masterclass e straordinario pagato (dopo 01, 02, 03)
-- timbrature.masterclass_min : minuti della giornata dedicati a Masterclass
--                              (funzioni aggiuntive, pagate come straordinario)
-- autorizzazioni.pagati_min  : ore in piu della settimana autorizzate come
--                              straordinario PAGATO (a parte dal saldo);
--                              "minuti" resta lo straordinario A CREDITO
-- ============================================================================

alter table public.timbrature    add column if not exists masterclass_min int;
alter table public.autorizzazioni add column if not exists pagati_min int not null default 0;
