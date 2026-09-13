-- ============================================================================
-- Registro presenze — Straordinario abbinato a un debito preciso (dopo 01..13)
-- timbrature.recupero : a quale debito va lo straordinario di quel giorno.
--   'deb:AAAA-MM-GG'  = debito della settimana che inizia quel lunedì
--   'rip:AAAA-MM-GG'  = riposo compensativo preso quel giorno
--   'iniziale'        = debito del saldo iniziale d'anno
--   null              = nessuna scelta: vale l'ordine automatico (prima i più vecchi)
-- ============================================================================

alter table public.timbrature add column if not exists recupero text;
