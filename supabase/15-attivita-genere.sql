-- ============================================================================
-- Registro presenze — Blocchi orari e promemoria nel calendario (dopo 01..14)
-- eventi.genere : che cosa e' la riga del calendario.
--   null          = attivita' normale (con o senza persona)
--   'blocco'      = fascia oraria bloccata: li' non si possono mettere attivita'
--   'promemoria'  = promemoria a un'ora precisa, senza durata
-- ============================================================================

alter table public.eventi add column if not exists genere text
  check (genere in ('blocco', 'promemoria'));
