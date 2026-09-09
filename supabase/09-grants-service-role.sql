-- ============================================================================
-- Registro presenze — Permessi del ruolo di servizio (da eseguire dopo 01..08)
-- La funzione server "invia-avvisi" legge il database con la secret key del
-- progetto (ruolo service_role). In questo progetto i permessi sulle tabelle
-- non sono concessi di default: senza questo script la funzione risponde
-- "permission denied for table eventi".
-- ============================================================================

grant usage on schema public to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public
  grant usage, select on sequences to service_role;
