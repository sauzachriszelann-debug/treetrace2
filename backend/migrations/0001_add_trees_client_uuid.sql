-- ============================================================================
-- Migration 0001: add trees.client_uuid for idempotent tree submissions (G2)
-- ============================================================================
-- STATUS: NOT YET APPLIED. This file is a reviewed artifact; executing it is a
-- separately approved, user-performed action. The application refuses to
-- start against a PostgreSQL database where this migration is missing
-- (fail-fast preflight in app/main.py: verify_idempotency_schema).
--
-- Target: PostgreSQL (Aiven). Requires PostgreSQL 9.6+ for ADD COLUMN IF NOT
-- EXISTS (Aiven deployments are PG 12+).
--
-- PRE-WORK (user, before running anything):
--   1. Confirm which database each backend uses: Render service "treetrace2"
--      and Vercel project "treetrace2backend" must have their DATABASE_URL
--      host:port/database compared in the respective dashboards. If they
--      differ, run this migration against EACH database.
--   2. Back up the trees table:
--        pg_dump "$DATABASE_URL" --table=trees > trees_backup_$(date +%Y%m%d).sql
--
-- ── PREFLIGHT (read-only; safe to run at any time) ─────────────────────────
--   SELECT current_database(), version();
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'trees' AND column_name = 'client_uuid';
--     -- expect: 0 rows before migration
--
-- ── APPLY (single transaction) ─────────────────────────────────────────────
BEGIN;

ALTER TABLE trees ADD COLUMN IF NOT EXISTS client_uuid VARCHAR(36);

-- Unique index is the idempotency source of truth. NULLs are distinct in
-- PostgreSQL, so legacy rows (client_uuid IS NULL) never collide.
CREATE UNIQUE INDEX IF NOT EXISTS ux_trees_client_uuid ON trees (client_uuid);

COMMIT;

-- ── VERIFY ─────────────────────────────────────────────────────────────────
--   SELECT column_name, data_type, character_maximum_length, is_nullable
--     FROM information_schema.columns
--     WHERE table_name = 'trees' AND column_name = 'client_uuid';
--     -- expect: varchar, 36, YES
--   SELECT indexname FROM pg_indexes
--     WHERE tablename = 'trees' AND indexname = 'ux_trees_client_uuid';
--     -- expect: 1 row
--   SELECT count(*) FROM trees WHERE client_uuid IS NOT NULL;
--     -- expect: 0 immediately after migration
--
-- ── DEPLOYMENT ORDER ───────────────────────────────────────────────────────
--   1. Backup (above).  2. Run preflight.  3. APPLY once per database.
--   4. Deploy Render backend; confirm log line "preflight OK: trees.client_uuid
--      present with unique index".  5. Deploy Vercel backend; confirm again.
--   6. Only then release updated mobile/web clients. (Old clients send no
--      client_uuid and old backends ignore the extra JSON key, so every
--      intermediate state is compatible — but backends must land first.)
--
-- ── CONCURRENCY VERIFICATION (staging; replaces SQLite smoke coverage) ─────
--   Fire parallel identical requests carrying the same client_uuid and assert
--   exactly one 201, one-or-more 200s with header Idempotent-Replay: true,
--   and a single resulting row:
--     UUID=$(python -c "import uuid;print(uuid.uuid4())")
--     PAYLOAD="{\"common_name\":\"Narra\",\"client_uuid\":\"$UUID\"}"
--     seq 10 | xargs -P 10 -I{} curl -s -o /dev/null -w "%{http_code}\n" \
--       -X POST "$BACKEND_URL/api/trees/" -H "Authorization: Bearer $TOKEN" \
--       -H "Content-Type: application/json" -d "$PAYLOAD"
--     # expect: one 201, nine 200
--
-- ── ROLLBACK (LAST RESORT — read first) ────────────────────────────────────
-- PREFERRED ROLLBACK: redeploy the previous application build and RETAIN this
-- schema. The column is nullable and old code never references it, so old and
-- new backends coexist safely against the migrated database.
-- Dropping the column DESTROYS the client_uuid -> tree mapping, breaking
-- idempotency for any in-flight client submissions; there is no recovery of
-- those keys. Only if the schema itself must be reverted:
--   DROP INDEX IF EXISTS ux_trees_client_uuid;
--   ALTER TABLE trees DROP COLUMN IF EXISTS client_uuid;
