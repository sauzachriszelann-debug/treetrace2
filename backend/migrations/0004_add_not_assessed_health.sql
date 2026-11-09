-- Run before deploying the Not assessed feature. PostgreSQL only.
-- SQLAlchemy persists enum MEMBER NAMES, so NotAssessed is the enum label;
-- the API/display value is "Not assessed". Existing rows are never rewritten.
-- Commit enum additions before application requests use the new value.
BEGIN;
DO $$
DECLARE
    col record;
BEGIN
    FOR col IN
        SELECT table_schema, table_name, column_name, data_type,
               udt_schema, udt_name, character_maximum_length
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND ((table_name = 'trees' AND column_name = 'health_status')
            OR (table_name = 'health_logs' AND column_name = 'condition'))
    LOOP
        IF col.data_type = 'USER-DEFINED' THEN
            EXECUTE format('ALTER TYPE %I.%I ADD VALUE IF NOT EXISTS %L',
                           col.udt_schema, col.udt_name, 'NotAssessed');
        ELSIF col.data_type = 'character varying'
              AND col.character_maximum_length < 40 THEN
            EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I TYPE VARCHAR(40)',
                           col.table_schema, col.table_name, col.column_name);
        END IF;
    END LOOP;
END $$;
COMMIT;

-- No backfill: historical Healthy/Fair/Poor values remain as recorded.
