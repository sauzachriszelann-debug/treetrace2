import re

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from app.db.database import engine, Base
from app.core.config import settings
from app.api.routes import auth, trees, health_logs, users, storage, public, identify, evaluation, planting, tree_submissions

# Import all models
from app.models import user, tree, health_log, evaluation_result, planting_recommendation, tree_submission
from app.models.unknown_species import UnknownSpecies

# --- REMOVED THE BLOCKING LINE FROM HERE ---
# Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="TreeTrace API",
    description="Geo-Spatial Tree Inventory System for Panabo City",
    version="1.0.0",
    redirect_slashes=False,
)


def sync_postgres_sequences():
    if not settings.SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
        return

    tables = ("users", "trees", "health_logs")
    with engine.begin() as conn:
        for table in tables:
            conn.execute(
                text(
                    f"""
                    SELECT setval(
                        pg_get_serial_sequence('{table}', 'id'),
                        COALESCE((SELECT MAX(id) FROM {table}), 1),
                        (SELECT COUNT(*) > 0 FROM {table})
                    )
                    """
                )
            )


def sync_subscription_columns():
    if not settings.SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
        return
    statements = (
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_plan VARCHAR(20) NOT NULL DEFAULT 'free'",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS upgrade_requested BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_identifications_today INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS unknown_submissions_today INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_usage_date DATE",
    )
    with engine.begin() as conn:
        for statement in statements:
            conn.execute(text(statement))


_IDEMPOTENCY_INDEX = "ux_trees_client_uuid"


def verify_idempotency_schema() -> None:
    """Fail fast unless the G2 idempotency schema is fully in place.

    Verifies, against a reachable PostgreSQL database:
      1. trees.client_uuid exists in the current schema;
      2. it is VARCHAR(36) and nullable;
      3. the index ux_trees_client_uuid exists;
      4. it is on trees in the current schema;
      5. it is UNIQUE;
      6. it covers exactly the client_uuid column - no extra/INCLUDE
         columns, no expression;
      7. it is valid (pg_index.indisvalid).

    Any missing or incorrect property raises RuntimeError naming every
    failed property: an unsafe database must never be silently accepted.
    A genuinely unreachable database keeps the historical
    tolerate-at-startup behaviour (logged, not fatal) so a transient
    outage cannot block boot. Once a connection is established, however,
    being unable to inspect the schema is itself fatal - that is the one
    deliberate strengthening of the old behaviour.
    """
    if not settings.SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
        return

    try:
        connection = engine.connect()
    except Exception as exc:
        print(f"preflight skipped: database unreachable ({exc})")
        return

    try:
        with connection:
            column = connection.execute(text(
                "SELECT data_type, character_maximum_length, is_nullable, "
                "       current_schema AS schema_name "
                "FROM information_schema.columns "
                "WHERE table_schema = current_schema "
                "  AND table_name = 'trees' "
                "  AND column_name = 'client_uuid'"
            )).first()
            index_rows = connection.execute(text(
                "SELECT t.relname AS table_name, "
                "       ns.nspname AS schema_name, "
                "       current_schema AS current_schema_name, "
                "       i.indisunique AS is_unique, "
                "       i.indisvalid AS is_valid, "
                "       i.indnkeyatts AS key_column_count, "
                "       i.indnatts AS total_column_count, "
                "       i.indexprs IS NOT NULL AS has_expression, "
                "       (SELECT a.attname FROM pg_attribute a "
                "         WHERE a.attrelid = i.indrelid "
                "           AND a.attnum = i.indkey[0]) AS first_column "
                "FROM pg_index i "
                "JOIN pg_class idx ON idx.oid = i.indexrelid "
                "JOIN pg_class t ON t.oid = i.indrelid "
                "JOIN pg_namespace ns ON ns.oid = t.relnamespace "
                "WHERE idx.relname = :index_name"
            ), {"index_name": _IDEMPOTENCY_INDEX}).fetchall()
    except Exception as exc:
        raise RuntimeError(
            "FATAL: preflight connected to the database but could not "
            f"inspect the idempotency schema ({exc}); refusing to start "
            "with an unverified database."
        ) from exc

    problems = []

    if column is None:
        problems.append("trees.client_uuid column is missing")
    else:
        data_type, max_length, is_nullable, _column_schema = column
        if data_type != "character varying":
            problems.append(
                f"trees.client_uuid is {data_type}, expected character varying"
            )
        elif max_length != 36:
            problems.append(
                f"trees.client_uuid length is {max_length}, expected 36"
            )
        if is_nullable != "YES":
            problems.append(
                "trees.client_uuid is NOT NULL; legacy clients would break it"
            )

    if not index_rows:
        problems.append(f"unique index {_IDEMPOTENCY_INDEX} is missing")
    elif len(index_rows) > 1:
        schemas = ", ".join(sorted({row[1] for row in index_rows}))
        problems.append(
            f"index name {_IDEMPOTENCY_INDEX} exists in multiple schemas "
            f"({schemas}); the idempotency index is ambiguous"
        )
    else:
        (table_name, schema_name, current_schema_name, is_unique, is_valid,
         key_count, total_count, has_expression, first_column) = index_rows[0]
        if table_name != "trees" or schema_name != current_schema_name:
            problems.append(
                f"index {_IDEMPOTENCY_INDEX} is on {schema_name}.{table_name}, "
                f"expected {current_schema_name}.trees"
            )
        if not is_unique:
            problems.append(f"index {_IDEMPOTENCY_INDEX} is not UNIQUE")
        if not is_valid:
            problems.append(
                f"index {_IDEMPOTENCY_INDEX} is marked INVALID (an interrupted "
                "CONCURRENTLY build leaves this behind); DROP INDEX it and "
                "re-run the migration"
            )
        if (has_expression or first_column != "client_uuid"
                or key_count != 1 or total_count != 1):
            problems.append(
                f"index {_IDEMPOTENCY_INDEX} does not cover exactly "
                f"trees.client_uuid (first column={first_column}, "
                f"key columns={key_count}, total columns={total_count}, "
                f"expression={bool(has_expression)})"
            )

    if problems:
        raise RuntimeError(
            "FATAL: unsafe idempotency schema: "
            + "; ".join(problems)
            + ". Run backend/migrations/0001_add_trees_client_uuid.sql "
            "before deploying this build."
        )
    print("preflight OK: trees.client_uuid present with unique index")


# ---------------------------------------------------------------------------
# G4 preflight: verify the tree_submissions schema by ACTUAL PROPERTIES
# (column types/lengths/nullability, CHECK expression, index uniqueness,
# validity, exact column sets and partial predicates) - never by object
# names alone (approved decision D7). PostgreSQL-only; SQLite test and dev
# environments are skipped, mirroring verify_idempotency_schema.
# ---------------------------------------------------------------------------

_SUBMISSION_STATUS_STATES = ("pending", "approved", "rejected", "linked")

# column name -> (data_type, character_maximum_length, is_nullable)
_SUBMISSION_COLUMNS = {
    "id": ("integer", None, "NO"),
    "client_uuid": ("character varying", 36, "YES"),
    "status": ("character varying", 40, "NO"),
    "source": ("character varying", 30, "YES"),
    "common_name": ("character varying", 150, "YES"),
    "scientific_name": ("character varying", 150, "YES"),
    "dbh_cm": ("double precision", None, "YES"),
    "height_m": ("double precision", None, "YES"),
    "health_status": ("character varying", 40, "YES"),
    "barangay": ("character varying", 120, "YES"),
    "city": ("character varying", 120, "YES"),
    "province": ("character varying", 120, "YES"),
    "lat": ("double precision", None, "YES"),
    "lng": ("double precision", None, "YES"),
    "photo_url": ("character varying", 500, "YES"),
    "date_recorded": ("date", None, "YES"),
    "notes": ("text", None, "YES"),
    "ai_candidates": ("text", None, "YES"),
    "review_overrides": ("text", None, "YES"),
    "reviewed_by_id": ("integer", None, "YES"),
    "review_reason": ("text", None, "YES"),
    "reviewed_at": ("timestamp with time zone", None, "YES"),
    "approved_tree_id": ("integer", None, "YES"),
    "source_unknown_species_id": ("integer", None, "YES"),
    "submitted_by_id": ("integer", None, "YES"),
    "created_at": ("timestamp with time zone", None, "NO"),
    "updated_at": ("timestamp with time zone", None, "YES"),
}

# users quota column checked alongside the table.
_USER_QUOTA_COLUMN = ("tree_submissions_today", ("integer", None, "NO"))

# index name -> (expected columns, expected partial predicate fragment or None)
_SUBMISSION_INDEXES = {
    "ux_tree_submissions_client_uuid": (("client_uuid",), None),
    "ux_tree_submissions_source_unknown_species": (
        ("source_unknown_species_id",),
        None,
    ),
    "ux_tree_submissions_approved": (
        ("approved_tree_id",),
        "status = 'approved'",
    ),
}


def _normalize_index_predicate(expr):
    """Reduce a PostgreSQL-declared partial-index predicate to a canonical,
    whitespace-free form for semantic comparison.

    PostgreSQL renders ``WHERE status = 'approved'`` on a varchar column as
    ``((status)::text = ('approved'::character varying)::text)`` (PG 16) or
    ``(status = 'approved'::text)`` (earlier). Both are semantically the same
    predicate, but the explicit casts and whitespace differ from the literal
    the verifier expects. Stripping whitespace and the redundant ``::text`` /
    ``::character varying`` / ``::varchar`` casts makes the three forms
    compare equal while leaving the column name, operator, and literal
    intact - so a genuinely wrong predicate (e.g. ``status = 'linked'``)
    still differs and is still rejected.
    """
    if not expr:
        return ""
    text = re.sub(
        r"::(?:character\s+varying|[A-Za-z_]+)(?:\s*\([^)]*\))?", "", expr
    )
    text = re.sub(r"\s+", "", text)
    return re.sub(r"[()]", "", text)


def verify_submission_schema() -> None:
    """Fail fast unless the G4 tree_submissions schema is fully in place.

    Verifies PROPERTIES, not names: every column's type, length and
    nullability; the status CHECK expression actually constrains to the four
    approved states; each index is unique, valid, covers exactly its expected
    column(s), and (for the approved-only index) carries the expected partial
    predicate. All failures are reported together.
    """
    if not settings.SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
        return

    try:
        connection = engine.connect()
    except Exception as exc:
        print(f"preflight skipped: database unreachable ({exc})")
        return

    try:
        with connection:
            column_rows = connection.execute(text(
                "SELECT table_name, column_name, data_type, "
                "       character_maximum_length, is_nullable "
                "FROM information_schema.columns "
                "WHERE table_schema = current_schema "
                "  AND table_name IN ('tree_submissions', 'users')"
            )).fetchall()
            check_rows = connection.execute(text(
                "SELECT conname, pg_get_constraintdef(oid) AS definition "
                "FROM pg_constraint "
                "WHERE conrelid = 'tree_submissions'::regclass "
                "  AND contype = 'c'"
            )).fetchall()
            index_rows = connection.execute(text(
                "SELECT idx.relname AS index_name, "
                "       t.relname AS table_name, "
                "       ns.nspname AS schema_name, "
                "       current_schema AS current_schema_name, "
                "       i.indisunique AS is_unique, "
                "       i.indisvalid AS is_valid, "
                "       i.indnkeyatts AS key_column_count, "
                "       i.indnatts AS total_column_count, "
                "       i.indexprs IS NOT NULL AS has_expression, "
                "       i.indpred IS NOT NULL AS has_predicate, "
                "       COALESCE(pg_get_expr(i.indpred, i.indrelid), '') "
                "           AS predicate, "
                "       (SELECT array_agg(a.attname ORDER BY ord.ordinality) "
                "          FROM unnest(i.indkey) "
                "               WITH ORDINALITY AS ord(attnum, ordinality) "
                "          JOIN pg_attribute a "
                "            ON a.attrelid = i.indrelid "
                "           AND a.attnum = ord.attnum) AS columns "
                "FROM pg_index i "
                "JOIN pg_class idx ON idx.oid = i.indexrelid "
                "JOIN pg_class t ON t.oid = i.indrelid "
                "JOIN pg_namespace ns ON ns.oid = t.relnamespace "
                "WHERE t.relname = 'tree_submissions'"
            )).fetchall()
    except Exception as exc:
        raise RuntimeError(
            "FATAL: preflight connected to the database but could not "
            f"inspect the G4 submission schema ({exc}); refusing to start "
            "with an unverified database."
        ) from exc

    problems = []

    actual_columns = {
        (row[0], row[1]): (row[2], row[3], row[4]) for row in column_rows
    }

    # 1. tree_submissions columns: presence, type, length, nullability.
    for name, expected in _SUBMISSION_COLUMNS.items():
        actual = actual_columns.get(("tree_submissions", name))
        if actual is None:
            problems.append(
                f"tree_submissions.{name} column is missing"
            )
            continue
        data_type, max_length, is_nullable = actual
        exp_type, exp_length, exp_nullable = expected
        if data_type != exp_type:
            problems.append(
                f"tree_submissions.{name} is {data_type}, expected {exp_type}"
            )
        elif exp_length is not None and max_length != exp_length:
            problems.append(
                f"tree_submissions.{name} length is {max_length}, "
                f"expected {exp_length}"
            )
        if is_nullable != exp_nullable:
            problems.append(
                f"tree_submissions.{name} nullability is {is_nullable}, "
                f"expected {exp_nullable}"
            )

    # 2. users.tree_submissions_today quota column.
    quota_name, quota_expected = _USER_QUOTA_COLUMN
    quota_actual = actual_columns.get(("users", quota_name))
    if quota_actual is None:
        problems.append(f"users.{quota_name} column is missing")
    else:
        data_type, max_length, is_nullable = quota_actual
        exp_type, exp_length, exp_nullable = quota_expected
        if data_type != exp_type or is_nullable != exp_nullable:
            problems.append(
                f"users.{quota_name} is ({data_type}, nullable={is_nullable}), "
                f"expected ({exp_type}, nullable={exp_nullable})"
            )

    # 3. status CHECK expression must constrain all four approved states.
    if not check_rows:
        problems.append(
            "CHECK constraint ck_tree_submissions_status is missing"
        )
    else:
        status_defs = [
            definition
            for conname, definition in check_rows
            if conname == "ck_tree_submissions_status"
        ]
        if not status_defs:
            problems.append(
                "CHECK constraint ck_tree_submissions_status is missing"
            )
        else:
            definition = status_defs[0]
            missing_states = [
                state
                for state in _SUBMISSION_STATUS_STATES
                if state not in definition
            ]
            # Whole-token match: "status" must appear as the constrained
            # column - a substring of "health_status" must not satisfy it.
            constrains_status = re.search(
                r"(?<![A-Za-z0-9_])status(?![A-Za-z0-9_])", definition
            )
            if not constrains_status or missing_states:
                problems.append(
                    "ck_tree_submissions_status does not constrain status "
                    f"to the approved states (definition={definition}, "
                    f"missing states={missing_states})"
                )

    # 4. Indexes: presence, table, schema, uniqueness, validity, exact
    #    columns, and the approved-only partial predicate.
    indexes_by_name = {}
    for row in index_rows:
        indexes_by_name.setdefault(row[0], []).append(row)

    for name, (exp_columns, exp_predicate) in _SUBMISSION_INDEXES.items():
        rows = indexes_by_name.get(name, [])
        if not rows:
            problems.append(f"index {name} is missing")
            continue
        if len(rows) > 1:
            schemas = ", ".join(sorted({row[2] for row in rows}))
            problems.append(
                f"index {name} exists in multiple schemas ({schemas}); "
                "it is ambiguous"
            )
            continue
        (index_name, table_name, schema_name, current_schema_name,
         is_unique, is_valid, key_count, total_count, has_expression,
         has_predicate, predicate, columns) = rows[0]
        if table_name != "tree_submissions" or schema_name != current_schema_name:
            problems.append(
                f"index {name} is on {schema_name}.{table_name}, "
                f"expected {current_schema_name}.tree_submissions"
            )
        if not is_unique:
            problems.append(f"index {name} is not UNIQUE")
        if not is_valid:
            problems.append(
                f"index {name} is marked INVALID (an interrupted "
                "CONCURRENTLY build leaves this behind); DROP INDEX it and "
                "re-run the migration"
            )
        actual_columns_tuple = tuple(columns or ())
        if (has_expression or actual_columns_tuple != exp_columns
                or key_count != len(exp_columns)
                or total_count != len(exp_columns)):
            problems.append(
                f"index {name} does not cover exactly "
                f"{list(exp_columns)} (columns={list(actual_columns_tuple)}, "
                f"key columns={key_count}, total columns={total_count}, "
                f"expression={bool(has_expression)})"
            )
        if exp_predicate is None:
            if has_predicate:
                problems.append(
                    f"index {name} is unexpectedly partial "
                    f"(predicate={predicate!r}); expected a full index"
                )
        else:
            if not has_predicate:
                problems.append(
                    f"index {name} is missing its partial predicate "
                    f"(expected {exp_predicate!r}); LINKED submissions "
                    "must not be constrained"
                )
            elif _normalize_index_predicate(exp_predicate) != _normalize_index_predicate(predicate):
                problems.append(
                    f"index {name} predicate is {predicate!r}, expected "
                    f"{exp_predicate!r}"
                )

    if problems:
        raise RuntimeError(
            "FATAL: unsafe G4 submission schema: "
            + "; ".join(problems)
            + ". Run backend/migrations/0002_add_tree_submissions.sql "
            "before deploying this build."
        )
    print("preflight OK: tree_submissions schema verified")


# Move database creation to a startup event so it doesn't freeze the server
@app.on_event("startup")
def startup_event():
    verify_idempotency_schema()
    # G4: runs BEFORE create_all, so an unmigrated PostgreSQL database fails
    # boot instead of letting create_all build an unconstrained substitute.
    verify_submission_schema()
    print("Attempting to connect to Aiven Database...")
    try:
        # This will create tables if they don't exist
        Base.metadata.create_all(bind=engine)
        sync_subscription_columns()
        sync_postgres_sequences()
        print("Database connection successful and tables synchronized!")
    except Exception as e:
        print("DATABASE CONNECTION ERROR:")
        print(e)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "https://treetrace-1o7l.onrender.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(auth.router,        prefix="/api/auth",        tags=["Auth"])
app.include_router(users.router,       prefix="/api/users",       tags=["Users"])
app.include_router(trees.router,       prefix="/api/trees",       tags=["Trees"])
app.include_router(health_logs.router, prefix="/api/health-logs", tags=["Health Logs"])
app.include_router(storage.router,     prefix="/api/storage",     tags=["Storage"])
app.include_router(public.router,      prefix="/api/public",      tags=["Public"])
app.include_router(identify.router,    prefix="/api/ai",          tags=["AI Identification"])
app.include_router(evaluation.router,  prefix="/api/evaluation",  tags=["Evaluation"])
app.include_router(planting.router,    prefix="/api/planting",    tags=["Planting Recommendations"])
app.include_router(tree_submissions.router, prefix="/api/tree-submissions", tags=["Tree Submissions"])


@app.get("/")
def root():
    return {"message": "TreeTrace API is running", "version": "1.0.0"}


@app.get("/api/health")
def health_check():
    return {"status": "ok"}
