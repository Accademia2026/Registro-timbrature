-- ============================================================================
-- Registro presenze — Permessi dei ruoli API (da eseguire dopo 01-schema.sql)
-- I progetti Supabase recenti non concedono più i permessi DML di default:
-- questo script dà al ruolo `authenticated` (utenti loggati) il minimo che
-- serve all'app — la RLS resta il vero confine tra un utente e l'altro.
-- Il ruolo `anon` (non loggati) resta senza alcun accesso: voluto.
-- ============================================================================

-- Utenti loggati: lettura/scrittura sulle tabelle (filtrate riga per riga
-- dalla RLS) e uso delle sequenze degli id generati.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Stessi permessi anche su eventuali tabelle/sequenze future.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

-- Igiene: via i permessi superflui presenti di default. TRUNCATE in
-- particolare NON è soggetto alla RLS (svuota l'intera tabella).
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
