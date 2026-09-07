-- ============================================================================
-- Registro presenze — Fine facoltativa di un periodo di orario (dopo 01..06)
-- periodi.valido_al : lunedi' dell'ultima settimana in cui vale il periodo;
--                     null = fino al cambio successivo
-- ============================================================================

alter table public.periodi add column if not exists valido_al date;
