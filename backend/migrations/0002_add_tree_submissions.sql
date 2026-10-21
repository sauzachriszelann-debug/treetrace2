-- ============================================================================
-- Migration 0002: tree_submissions (G4 pending review and approval) and
--                 users.tree_submissions_today (separate daily quota)
-- ============================================================================
-- STATUS: NOT YET APPLIED. This file is a reviewed artifact; executing it is
-- a separately approved, user-performed action. The application refuses to
-- start against a PostgreSQL database where this migration is missing or
-- wrong (fail-fast preflight in app/main.py: verify_submission_schema, which
-- checks actual table/column/constraint/index PROPERTIES, not just names).
--
-- Target: PostgreSQL (Aiven). Two databases must each receive this
-- migration (Render "treetrace2" and Vercel "treetrace2backend") - compare
-- DATABASE_URL host:port/database in both dashboards first.
--
-- PRE-WORK (user, before running anything):
--   1. Confirm migration 0001 is applied to the same database (G4 assumes
--      the G2 preflight is already enforced).
--   2. Back up the users and trees tables:
--        pg_dump "$DATABASE_URL" --table=users --table=trees \
--          > g4_backup_$(date +%Y%m%d).sql
--
-- ── PREFLIGHT (read-only; safe to run at any time) ───────────────────────────
--   SELECT current_database(), version();
--   SELECT to_regclass('tree_submissions');            -- expect: NULL
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'users' AND column_name = 'tree_submissions_today';
--     -- expect: 0 rows before migration
--
-- ── APPLY (single transaction) ───────────────────────────────────────────────
BEGIN;

CREATE TABLE IF NOT EXISTS tree_submissions (
    id                          SERIAL PRIMARY KEY,
    -- G2-style idempotency key; NULLs are distinct, so keyless rows never
    -- collide. Uniqueness prevents retry-duplicates, not human duplicates.
    client_uuid                 VARCHAR(36),
    -- State machine (app-enforced CAS + this CHECK):
    --   pending -> approved | rejected | linked ; rejected -> pending only.
    --   approved and linked are terminal.
    status                      VARCHAR(40) NOT NULL DEFAULT 'pending',
    source                      VARCHAR(30),
    -- Proposed tree payload; all nullable because evidence may be
    -- incomplete. common_name becomes mandatory only at approval time.
    common_name                 VARCHAR(150),
    scientific_name             VARCHAR(150),
    dbh_cm                      DOUBLE PRECISION,
    height_m                    DOUBLE PRECISION,
    health_status               VARCHAR(40) DEFAULT 'Healthy',
    barangay                    VARCHAR(120),
    city                        VARCHAR(120) DEFAULT 'Panabo City',
    province                    VARCHAR(120) DEFAULT 'Davao del Norte',
    lat                         DOUBLE PRECISION,
    lng                         DOUBLE PRECISION,
    photo_url                   VARCHAR(500),
    date_recorded               DATE,
    notes                       TEXT,
    ai_candidates               TEXT,
    -- Reviewer corrections (JSON), stored SEPARATELY: submitted evidence is
    -- write-once and never modified by any endpoint.
    review_overrides            TEXT,
    reviewed_by_id              INTEGER REFERENCES users(id),
    review_reason               TEXT,
    reviewed_at                 TIMESTAMPTZ,
    -- Tree this submission resolved to: the NEW tree created on approval, or
    -- the EXISTING tree recorded on link. No FK on purpose - trees may be
    -- deleted by admins and terminal-state provenance must not be rewritten.
    approved_tree_id            INTEGER,
    -- Path B provenance: the unknown-species entry this was converted from.
    -- UNIQUE: one entry yields at most one submission (conversion safety).
    source_unknown_species_id   INTEGER REFERENCES unknown_species(id),
    submitted_by_id             INTEGER REFERENCES users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ,
    CONSTRAINT ck_tree_submissions_status
        CHECK (status IN ('pending', 'approved', 'rejected', 'linked')),
    CONSTRAINT ux_tree_submissions_client_uuid
        UNIQUE (client_uuid),
    CONSTRAINT ux_tree_submissions_source_unknown_species
        UNIQUE (source_unknown_species_id)
);

-- Safeguard A: uniqueness applies ONLY to APPROVED submissions, which each
-- own exactly one NEW tree they created. LINKED submissions deliberately
-- share approved_tree_id freely - many submissions may reference the same
-- existing tree - so the partial predicate keeps them out of the index.
CREATE UNIQUE INDEX IF NOT EXISTS ux_tree_submissions_approved
    ON tree_submissions (approved_tree_id)
    WHERE status = 'approved';

-- Decision 10: separate daily tree-submission quota. NOT NULL DEFAULT 0 so
-- old backend code runs unharmed during deploy skew; all three user
-- counters roll over together on the shared ai_usage_date column.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS tree_submissions_today INTEGER NOT NULL DEFAULT 0;

COMMIT;

-- ── VERIFY ───────────────────────────────────────────────────────────────────
--   SELECT column_name, data_type, character_maximum_length, is_nullable
--     FROM information_schema.columns
--     WHERE table_name = 'tree_submissions' ORDER BY ordinal_position;
--     -- expect: 27 columns matching app/models/tree_submission.py
--   SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--     WHERE conrelid = 'tree_submissions'::regclass;
--     -- expect: ck_tree_submissions_status (4 states), the two UNIQUE
--     --         constraints, plus PK/FKs
--   SELECT indexname, indexdef FROM pg_indexes
--     WHERE tablename = 'tree_submissions';
--     -- expect: ux_tree_submissions_approved partial on (approved_tree_id)
--   SELECT count(*) FROM users WHERE tree_submissions_today IS NULL;
--     -- expect: 0
--
-- ── DEPLOYMENT ORDER ─────────────────────────────────────────────────────────
--   1. Backup (above).  2. Run preflight SELECTs.  3. APPLY once per
--   database.  4. Deploy backend; confirm log lines "preflight OK:
--   trees.client_uuid ..." AND "preflight OK: tree_submissions schema
--   verified".  5. Only then release updated web/mobile clients. (Old
--   clients never call the new endpoints; old backends ignore the new
--   table and column, so every intermediate state is compatible - but the
--   backends must land first, because the new preflight FAILS BOOT on a
--   database missing this migration.)
--
-- ── ROLLBACK (LAST RESORT - read first) ──────────────────────────────────────
-- PREFERRED ROLLBACK: redeploy the previous application build and RETAIN
-- this schema. The table and column are ignored by old code, so old and new
-- backends coexist safely against the migrated database. Dropping the table
-- DESTROYS the citizen submission history and every approval audit record;
-- there is no recovery. Only if the schema itself must be reverted:
--   DROP TABLE IF EXISTS tree_submissions;
--   ALTER TABLE users DROP COLUMN IF EXISTS tree_submissions_today;
