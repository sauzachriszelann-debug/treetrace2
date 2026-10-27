"""Focused tests for the G4 startup preflight (approved decision D7).

verify_submission_schema() is only meaningful on PostgreSQL and the test
suite runs on SQLite, so these tests drive it through a fake engine whose
connection returns programmed catalog rows. Each test targets exactly one
schema property to prove the preflight verifies ACTUAL table, column,
constraint and index PROPERTIES - never object names alone.
"""

import pytest

import app.main as main_module


# ---------------------------------------------------------------------------
# Valid catalog fixtures (all 27 tree_submissions columns + users quota)
# ---------------------------------------------------------------------------

def _column(table, name, data_type, max_length, is_nullable):
    return (table, name, data_type, max_length, is_nullable)


VALID_COLUMNS = [
    _column("tree_submissions", "id", "integer", None, "NO"),
    _column("tree_submissions", "client_uuid", "character varying", 36, "YES"),
    _column("tree_submissions", "status", "character varying", 40, "NO"),
    _column("tree_submissions", "source", "character varying", 30, "YES"),
    _column("tree_submissions", "common_name", "character varying", 150, "YES"),
    _column("tree_submissions", "scientific_name", "character varying", 150, "YES"),
    _column("tree_submissions", "dbh_cm", "double precision", None, "YES"),
    _column("tree_submissions", "height_m", "double precision", None, "YES"),
    _column("tree_submissions", "health_status", "character varying", 40, "YES"),
    _column("tree_submissions", "barangay", "character varying", 120, "YES"),
    _column("tree_submissions", "city", "character varying", 120, "YES"),
    _column("tree_submissions", "province", "character varying", 120, "YES"),
    _column("tree_submissions", "lat", "double precision", None, "YES"),
    _column("tree_submissions", "lng", "double precision", None, "YES"),
    _column("tree_submissions", "photo_url", "character varying", 500, "YES"),
    _column("tree_submissions", "date_recorded", "date", None, "YES"),
    _column("tree_submissions", "notes", "text", None, "YES"),
    _column("tree_submissions", "ai_candidates", "text", None, "YES"),
    _column("tree_submissions", "review_overrides", "text", None, "YES"),
    _column("tree_submissions", "reviewed_by_id", "integer", None, "YES"),
    _column("tree_submissions", "review_reason", "text", None, "YES"),
    _column("tree_submissions", "reviewed_at", "timestamp with time zone", None, "YES"),
    _column("tree_submissions", "approved_tree_id", "integer", None, "YES"),
    _column("tree_submissions", "source_unknown_species_id", "integer", None, "YES"),
    _column("tree_submissions", "submitted_by_id", "integer", None, "YES"),
    _column("tree_submissions", "created_at", "timestamp with time zone", None, "NO"),
    _column("tree_submissions", "updated_at", "timestamp with time zone", None, "YES"),
    _column("users", "tree_submissions_today", "integer", None, "NO"),
]

# (conname, pg_get_constraintdef)
VALID_CHECK = (
    "ck_tree_submissions_status",
    "CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, "
    "'rejected'::text, 'linked'::text])))",
)

# index row shape:
# (index_name, table_name, schema_name, current_schema_name, is_unique,
#  is_valid, key_column_count, total_column_count, has_expression,
#  has_predicate, predicate, columns)
def _index(name, columns, *, unique=True, valid=True, predicate=None):
    return (
        name,
        "tree_submissions",
        "public",
        "public",
        unique,
        valid,
        len(columns),
        len(columns),
        False,
        predicate is not None,
        predicate or "",
        tuple(columns),
    )


VALID_INDEXES = [
    _index("ux_tree_submissions_client_uuid", ["client_uuid"]),
    _index(
        "ux_tree_submissions_source_unknown_species",
        ["source_unknown_species_id"],
    ),
    _index(
        "ux_tree_submissions_approved",
        ["approved_tree_id"],
        # PG 16 renders a varchar partial predicate with explicit casts on
        # both sides. The verifier must accept this normalized form (and the
        # earlier PG `(status = 'approved'::text)` form) as equivalent to the
        # intended `status = 'approved'`.
        predicate="((status)::text = ('approved'::character varying)::text)",
    ),
]


class _FakeResult:
    def __init__(self, rows):
        self._rows = list(rows)

    def first(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return list(self._rows)


class _FakeConnection:
    def __init__(self, column_rows=(), check_rows=(), index_rows=(), query_error=None):
        self._column_rows = list(column_rows)
        self._check_rows = list(check_rows)
        self._index_rows = list(index_rows)
        self._query_error = query_error

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False

    def execute(self, statement, *args, **kwargs):
        if self._query_error is not None:
            raise self._query_error
        sql = str(statement)
        if "information_schema.columns" in sql:
            return _FakeResult(self._column_rows)
        if "pg_constraint" in sql:
            return _FakeResult(self._check_rows)
        if "pg_index" in sql:
            return _FakeResult(self._index_rows)
        raise AssertionError(f"unexpected preflight query: {sql}")


class _FakeEngine:
    def __init__(self, connection=None, connect_error=None):
        self._connection = connection
        self._connect_error = connect_error

    def connect(self):
        if self._connect_error is not None:
            raise self._connect_error
        return self._connection


def _run_preflight(
    monkeypatch,
    *,
    column_rows=VALID_COLUMNS,
    check_rows=(VALID_CHECK,),
    index_rows=VALID_INDEXES,
    connect_error=None,
    query_error=None,
    database_url="postgresql://preflight-test/db",
):
    monkeypatch.setattr(main_module.settings, "DATABASE_URL", database_url)
    engine = _FakeEngine(
        _FakeConnection(
            column_rows, check_rows, index_rows, query_error=query_error
        ),
        connect_error=connect_error,
    )
    monkeypatch.setattr(main_module, "engine", engine)
    return main_module.verify_submission_schema


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

def test_valid_schema_passes_preflight(monkeypatch, capsys):
    verify = _run_preflight(monkeypatch)

    verify()

    assert "preflight OK: tree_submissions schema verified" in capsys.readouterr().out


def test_non_postgresql_url_skips_preflight(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        database_url="sqlite:///local.db",
        connect_error=AssertionError("preflight must not touch a non-PG engine"),
    )

    verify()  # must not raise and must not call connect()


def test_unreachable_database_is_tolerated(monkeypatch, capsys):
    verify = _run_preflight(
        monkeypatch, connect_error=ConnectionRefusedError("connection refused")
    )

    verify()  # must not raise

    assert "preflight skipped: database unreachable" in capsys.readouterr().out


def test_connected_but_uninspectable_schema_is_fatal(monkeypatch):
    verify = _run_preflight(
        monkeypatch, query_error=Exception("catalog broken")
    )

    with pytest.raises(RuntimeError, match="could not inspect"):
        verify()


# ---------------------------------------------------------------------------
# Column properties (type, length, nullability, presence)
# ---------------------------------------------------------------------------

def test_missing_table_column_fails_clearly(monkeypatch):
    rows = [row for row in VALID_COLUMNS if row[1] != "status"]
    verify = _run_preflight(monkeypatch, column_rows=rows)

    with pytest.raises(RuntimeError, match="tree_submissions.status column is missing"):
        verify()


def test_wrong_column_type_fails_clearly(monkeypatch):
    rows = [
        ("tree_submissions", "status", "text", 40, "NO")
        if row[1] == "status" and row[0] == "tree_submissions"
        else row
        for row in VALID_COLUMNS
    ]
    verify = _run_preflight(monkeypatch, column_rows=rows)

    with pytest.raises(RuntimeError, match="tree_submissions.status is text, expected character varying"):
        verify()


def test_wrong_column_length_fails_clearly(monkeypatch):
    rows = [
        ("tree_submissions", "client_uuid", "character varying", 64, "YES")
        if row[1] == "client_uuid"
        else row
        for row in VALID_COLUMNS
    ]
    verify = _run_preflight(monkeypatch, column_rows=rows)

    with pytest.raises(RuntimeError, match="tree_submissions.client_uuid length is 64, expected 36"):
        verify()


def test_wrong_nullability_fails_clearly(monkeypatch):
    rows = [
        ("tree_submissions", "status", "character varying", 40, "YES")
        if row[1] == "status"
        else row
        for row in VALID_COLUMNS
    ]
    verify = _run_preflight(monkeypatch, column_rows=rows)

    with pytest.raises(RuntimeError, match="tree_submissions.status nullability is YES, expected NO"):
        verify()


def test_missing_quota_column_fails_clearly(monkeypatch):
    rows = [row for row in VALID_COLUMNS if row[0] != "users"]
    verify = _run_preflight(monkeypatch, column_rows=rows)

    with pytest.raises(RuntimeError, match="users.tree_submissions_today column is missing"):
        verify()


def test_multiple_column_problems_reported_together(monkeypatch):
    rows = [
        row
        for row in VALID_COLUMNS
        if row[1] not in ("status", "review_reason")
    ]
    verify = _run_preflight(monkeypatch, column_rows=rows)

    with pytest.raises(RuntimeError) as excinfo:
        verify()
    message = str(excinfo.value)
    assert "tree_submissions.status column is missing" in message
    assert "tree_submissions.review_reason column is missing" in message


# ---------------------------------------------------------------------------
# Status CHECK constraint
# ---------------------------------------------------------------------------

def test_missing_check_constraint_fails_clearly(monkeypatch):
    verify = _run_preflight(monkeypatch, check_rows=())

    with pytest.raises(
        RuntimeError, match="ck_tree_submissions_status is missing"
    ):
        verify()


def test_check_missing_a_state_fails_clearly(monkeypatch):
    weakened = (
        "ck_tree_submissions_status",
        "CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, "
        "'rejected'::text])))",
    )
    verify = _run_preflight(monkeypatch, check_rows=(weakened,))

    with pytest.raises(RuntimeError, match="missing states.*linked"):
        verify()


def test_check_on_wrong_column_fails_clearly(monkeypatch):
    wrong = (
        "ck_tree_submissions_status",
        "CHECK ((health_status = ANY (ARRAY['pending'::text, 'approved'::text,"
        " 'rejected'::text, 'linked'::text])))",
    )
    verify = _run_preflight(monkeypatch, check_rows=(wrong,))

    with pytest.raises(RuntimeError, match="does not constrain status"):
        verify()


# ---------------------------------------------------------------------------
# Index properties
# ---------------------------------------------------------------------------

def test_missing_index_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=[row for row in VALID_INDEXES if "approved" not in row[0]],
    )

    with pytest.raises(
        RuntimeError, match="index ux_tree_submissions_approved is missing"
    ):
        verify()


def test_non_unique_index_fails_clearly(monkeypatch):
    rows = [
        _index(
            "ux_tree_submissions_client_uuid",
            ["client_uuid"],
            unique=False,
        )
    ] + VALID_INDEXES[1:]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(
        RuntimeError, match="ux_tree_submissions_client_uuid is not UNIQUE"
    ):
        verify()


def test_invalid_index_fails_clearly(monkeypatch):
    rows = [
        VALID_INDEXES[0],
        _index(
            "ux_tree_submissions_source_unknown_species",
            ["source_unknown_species_id"],
            valid=False,
        ),
        VALID_INDEXES[2],
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_source_unknown_species is marked INVALID"):
        verify()


def test_index_on_wrong_column_fails_clearly(monkeypatch):
    rows = [
        _index("ux_tree_submissions_client_uuid", ["id"]),
        VALID_INDEXES[1],
        VALID_INDEXES[2],
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_client_uuid does not cover exactly"):
        verify()


def test_index_with_extra_columns_fails_clearly(monkeypatch):
    rows = [
        _index(
            "ux_tree_submissions_client_uuid",
            ["client_uuid", "status"],
        ),
        VALID_INDEXES[1],
        VALID_INDEXES[2],
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="does not cover exactly"):
        verify()


def test_approved_index_missing_predicate_fails_clearly(monkeypatch):
    """Safeguard A lives in this predicate: without it, LINKED submissions
    sharing a tree would be wrongly rejected."""
    rows = VALID_INDEXES[:2] + [
        _index("ux_tree_submissions_approved", ["approved_tree_id"])
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_approved is missing its partial predicate"):
        verify()


def test_approved_index_wrong_predicate_fails_clearly(monkeypatch):
    rows = VALID_INDEXES[:2] + [
        _index(
            "ux_tree_submissions_approved",
            ["approved_tree_id"],
            predicate="(status = 'linked'::text)",
        )
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_approved predicate is"):
        verify()


def test_unexpectedly_partial_index_fails_clearly(monkeypatch):
    rows = [
        _index(
            "ux_tree_submissions_client_uuid",
            ["client_uuid"],
            predicate="(client_uuid IS NOT NULL)",
        ),
        VALID_INDEXES[1],
        VALID_INDEXES[2],
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_client_uuid is unexpectedly partial"):
        verify()


# ---------------------------------------------------------------------------
# Partial-predicate normalization (PG renders varchar predicates with casts)
# ---------------------------------------------------------------------------

def test_pg_normalized_cast_predicate_is_accepted(monkeypatch, capsys):
    """PG 16 renders `WHERE status = 'approved'` on varchar as
    `((status)::text = ('approved'::character varying)::text)`. This is
    semantically identical to the intended predicate and must pass."""
    rows = VALID_INDEXES[:2] + [
        _index(
            "ux_tree_submissions_approved",
            ["approved_tree_id"],
            predicate="((status)::text = ('approved'::character varying)::text)",
        )
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    verify()  # must not raise
    assert "preflight OK: tree_submissions schema verified" in capsys.readouterr().out


def test_pg_earlier_cast_predicate_is_accepted(monkeypatch, capsys):
    """Earlier PG versions render the same predicate as
    `(status = 'approved'::text)` - also semantically identical, also accepted."""
    rows = VALID_INDEXES[:2] + [
        _index(
            "ux_tree_submissions_approved",
            ["approved_tree_id"],
            predicate="(status = 'approved'::text)",
        )
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    verify()  # must not raise
    assert "preflight OK: tree_submissions schema verified" in capsys.readouterr().out


def test_wrong_predicate_still_rejected_despite_casts(monkeypatch):
    """Normalization must not weaken the check: a wrong literal (linked,
    not approved) still fails even when PG adds casts/whitespace."""
    rows = VALID_INDEXES[:2] + [
        _index(
            "ux_tree_submissions_approved",
            ["approved_tree_id"],
            predicate="( (status)::text = ('linked'::character varying)::text )",
        )
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_approved predicate is"):
        verify()


def test_wrong_column_in_predicate_still_rejected(monkeypatch):
    """A predicate on a different column (health_status) must still fail,
    even with casts applied."""
    rows = VALID_INDEXES[:2] + [
        _index(
            "ux_tree_submissions_approved",
            ["approved_tree_id"],
            predicate="((health_status)::text = ('approved'::character varying)::text)",
        )
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="ux_tree_submissions_approved predicate is"):
        verify()


def test_index_on_wrong_table_fails_clearly(monkeypatch):
    rows = [
        (
            "ux_tree_submissions_client_uuid", "trees", "public", "public",
            True, True, 1, 1, False, False, "", ("client_uuid",),
        ),
        VALID_INDEXES[1],
        VALID_INDEXES[2],
    ]
    verify = _run_preflight(monkeypatch, index_rows=rows)

    with pytest.raises(RuntimeError, match="is on public.trees, expected public.tree_submissions"):
        verify()
