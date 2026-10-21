"""Focused tests for the hardened G2 startup preflight.

verify_idempotency_schema() is only meaningful on PostgreSQL, and the test
suite runs on SQLite, so these tests drive it through a fake engine whose
connection returns programmed catalog rows. Each test targets exactly one
schema property to prove the preflight names the failed property instead of
silently accepting an unsafe database.
"""

import pytest

import app.main as main_module


# (data_type, character_maximum_length, is_nullable, schema_name)
VALID_COLUMN = ("character varying", 36, "YES", "public")
# (table, index_schema, current_schema, unique, valid, key_cols, total_cols,
#  expression, first_column)
VALID_INDEX = ("trees", "public", "public", True, True, 1, 1, False, "client_uuid")


class _FakeResult:
    def __init__(self, rows):
        self._rows = list(rows)

    def first(self):
        return self._rows[0] if self._rows else None

    def fetchall(self):
        return list(self._rows)


class _FakeConnection:
    def __init__(self, column_rows=(), index_rows=(), query_error=None):
        self._column_rows = list(column_rows)
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
    column_rows=(VALID_COLUMN,),
    index_rows=(VALID_INDEX,),
    connect_error=None,
    query_error=None,
    database_url="postgresql://preflight-test/db",
):
    monkeypatch.setattr(main_module.settings, "DATABASE_URL", database_url)
    engine = _FakeEngine(
        _FakeConnection(column_rows, index_rows, query_error=query_error),
        connect_error=connect_error,
    )
    monkeypatch.setattr(main_module, "engine", engine)
    return main_module.verify_idempotency_schema


def test_valid_schema_passes_preflight(monkeypatch, capsys):
    verify = _run_preflight(monkeypatch)

    verify()

    assert "preflight OK" in capsys.readouterr().out


def test_missing_column_fails_clearly(monkeypatch):
    verify = _run_preflight(monkeypatch, column_rows=())

    with pytest.raises(RuntimeError, match="trees.client_uuid column is missing"):
        verify()


def test_wrong_column_type_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch, column_rows=(("text", None, "YES", "public"),)
    )

    with pytest.raises(RuntimeError, match="expected character varying"):
        verify()


def test_wrong_column_length_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch, column_rows=(("character varying", 64, "YES", "public"),)
    )

    with pytest.raises(RuntimeError, match="length is 64, expected 36"):
        verify()


def test_not_nullable_column_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch, column_rows=(("character varying", 36, "NO", "public"),)
    )

    with pytest.raises(RuntimeError, match="is NOT NULL"):
        verify()


def test_missing_index_fails_clearly(monkeypatch):
    verify = _run_preflight(monkeypatch, index_rows=())

    with pytest.raises(
        RuntimeError, match="unique index ux_trees_client_uuid is missing"
    ):
        verify()


def test_index_on_wrong_table_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("users", "public", "public", True, True, 1, 1, False, "client_uuid"),),
    )

    with pytest.raises(RuntimeError, match="on public.users"):
        verify()


def test_index_in_wrong_schema_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("trees", "other", "public", True, True, 1, 1, False, "client_uuid"),),
    )

    with pytest.raises(RuntimeError, match="on other.trees"):
        verify()


def test_non_unique_index_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("trees", "public", "public", False, True, 1, 1, False, "client_uuid"),),
    )

    with pytest.raises(RuntimeError, match="is not UNIQUE"):
        verify()


def test_invalid_index_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("trees", "public", "public", True, False, 1, 1, False, "client_uuid"),),
    )

    with pytest.raises(RuntimeError, match="INVALID"):
        verify()


def test_index_on_wrong_column_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("trees", "public", "public", True, True, 1, 1, False, "id"),),
    )

    with pytest.raises(RuntimeError, match="does not cover exactly"):
        verify()


def test_index_with_extra_columns_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("trees", "public", "public", True, True, 1, 2, False, "client_uuid"),),
    )

    with pytest.raises(RuntimeError, match="does not cover exactly"):
        verify()


def test_expression_index_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(("trees", "public", "public", True, True, 1, 1, True, "client_uuid"),),
    )

    with pytest.raises(RuntimeError, match="does not cover exactly"):
        verify()


def test_same_index_name_in_two_schemas_fails_clearly(monkeypatch):
    verify = _run_preflight(
        monkeypatch,
        index_rows=(
            ("trees", "public", "public", True, True, 1, 1, False, "client_uuid"),
            ("trees", "other", "public", True, True, 1, 1, False, "client_uuid"),
        ),
    )

    with pytest.raises(RuntimeError, match="multiple schemas"):
        verify()


def test_unreachable_database_is_tolerated(monkeypatch, capsys):
    """Historical behaviour: a genuine connection failure logs and returns."""
    verify = _run_preflight(
        monkeypatch, connect_error=ConnectionRefusedError("connection refused")
    )

    verify()  # must not raise

    output = capsys.readouterr().out
    assert "preflight skipped: database unreachable" in output


def test_connected_but_uninspectable_schema_is_fatal(monkeypatch):
    """Once connected, an inspection failure must NOT masquerade as
    'unreachable' and silently accept an unverified database."""
    verify = _run_preflight(monkeypatch, query_error=Exception("catalog broken"))

    with pytest.raises(RuntimeError, match="could not inspect"):
        verify()


def test_non_postgresql_url_skips_preflight(monkeypatch):
    """SQLite/local development is untouched: the engine is never consulted."""
    verify = _run_preflight(
        monkeypatch,
        database_url="sqlite:///local.db",
        connect_error=AssertionError("preflight must not touch a non-PG engine"),
    )

    verify()  # must not raise and must not call connect()
