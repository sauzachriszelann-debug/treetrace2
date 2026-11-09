"""Read-only deployment check for the additive health-status migration."""
from sqlalchemy import text


def verify_health_status_schema(engine):
    if engine.dialect.name != 'postgresql':
        return
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT c.table_name, c.column_name, c.data_type,
                   c.character_maximum_length,
                   EXISTS (
                       SELECT 1 FROM pg_enum e
                       JOIN pg_type t ON t.oid = e.enumtypid
                       JOIN pg_namespace n ON n.oid = t.typnamespace
                       WHERE n.nspname = c.udt_schema AND t.typname = c.udt_name
                         AND e.enumlabel = 'NotAssessed'
                   ) AS accepts_not_assessed
            FROM information_schema.columns c
            WHERE c.table_schema = current_schema()
              AND ((c.table_name = 'trees' AND c.column_name = 'health_status')
                OR (c.table_name = 'health_logs' AND c.column_name = 'condition'))
        """)).mappings().all()
    for row in rows:
        unsupported_enum = row['data_type'] == 'USER-DEFINED' and not row['accepts_not_assessed']
        too_short = (row['data_type'] == 'character varying'
                     and row['character_maximum_length'] is not None
                     and row['character_maximum_length'] < 12)
        if unsupported_enum or too_short:
            raise RuntimeError(
                'Health status schema needs migration: run '
                'backend/migrations/0004_add_not_assessed_health.sql before deployment.')
