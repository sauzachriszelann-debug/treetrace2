from collections.abc import Callable, Generator
import os
from typing import Any

os.environ.setdefault("TESTING", "true")

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.routes import auth, health_logs, public, storage, trees
from app.core.security import get_current_user
from app.db.database import Base, get_db
from app.models.health_log import HealthLog
from app.models.tree import Tree
from app.models.user import User, UserRole


@pytest.fixture
def db_session() -> Generator[Session, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    session = sessionmaker(autocommit=False, autoflush=False, bind=engine)()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


@pytest.fixture
def api_app(db_session: Session) -> Generator[FastAPI, None, None]:
    app = FastAPI()
    app.include_router(auth.router, prefix="/api/auth")
    app.include_router(trees.router, prefix="/api/trees")
    app.include_router(health_logs.router, prefix="/api/health-logs")
    app.include_router(public.router, prefix="/api/public")
    app.include_router(storage.router, prefix="/api/storage")

    def override_get_db() -> Generator[Session, None, None]:
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    try:
        yield app
    finally:
        app.dependency_overrides.clear()


@pytest.fixture
def client(api_app: FastAPI) -> Generator[TestClient, None, None]:
    with TestClient(api_app) as test_client:
        yield test_client


@pytest.fixture
def auth_as(api_app: FastAPI, db_session: Session) -> Callable[[UserRole], User]:
    def set_user(role: UserRole) -> User:
        user = User(
            full_name=f"{role.value} test user",
            email=f"{role.value}-{db_session.query(User).count()}@example.test",
            hashed_password="test-password-hash",
            role=role,
            is_active=True,
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        api_app.dependency_overrides[get_current_user] = lambda: user
        return user

    return set_user


@pytest.fixture
def concurrency_app(tmp_path) -> Generator[FastAPI, None, None]:
    """App wired to a file-based SQLite with per-request sessions.

    The shared ``api_app`` fixture uses one session for every request and
    cannot exercise concurrent idempotency handling.
    """
    engine = create_engine(
        f"sqlite:///{tmp_path / 'concurrency.db'}",
        connect_args={"check_same_thread": False, "timeout": 30},
    )

    # WAL plus a busy timeout lets two write transactions serialize instead of
    # hitting SQLite's shared-lock upgrade deadlock (which surfaces as an
    # uncatchable "database is locked" under plain rollback journal mode).
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=30000")
        cursor.close()

    Base.metadata.create_all(bind=engine)
    TestSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    app = FastAPI()
    app.include_router(trees.router, prefix="/api/trees")

    def override_get_db():
        session = TestSession()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db

    admin_session = TestSession()
    admin = User(
        full_name="Concurrency Admin",
        email="concurrency-admin@example.test",
        hashed_password="test-password-hash",
        role=UserRole.admin,
        is_active=True,
    )
    admin_session.add(admin)
    admin_session.commit()
    # Keep the admin session open until teardown: the request handlers read
    # current_user.id/.role, which would raise on a closed, expired instance.
    admin_session.refresh(admin)

    app.dependency_overrides[get_current_user] = lambda: admin
    try:
        yield app
    finally:
        app.dependency_overrides.clear()
        admin_session.close()
        engine.dispose()


@pytest.fixture
def admin_user(auth_as: Callable[[UserRole], User]) -> User:
    return auth_as(UserRole.admin)


@pytest.fixture
def field_worker_user(auth_as: Callable[[UserRole], User]) -> User:
    return auth_as(UserRole.field_worker)


@pytest.fixture
def citizen_user(auth_as: Callable[[UserRole], User]) -> User:
    return auth_as(UserRole.citizen)


@pytest.fixture
def tree_payload() -> dict[str, Any]:
    return {
        "common_name": "Narra",
        "scientific_name": "Pterocarpus indicus",
        "health_status": "Healthy",
        "barangay": "New Visayas",
        "dbh_cm": 24.0,
        "height_m": 9.0,
        "notes": "Internal field note",
    }


@pytest.fixture
def create_tree(
    client: TestClient,
    auth_as: Callable[[UserRole], User],
    tree_payload: dict[str, Any],
) -> Callable[..., dict[str, Any]]:
    def create(role: UserRole = UserRole.admin, **overrides: Any) -> dict[str, Any]:
        auth_as(role)
        payload = {**tree_payload, **overrides}
        response = client.post("/api/trees/", json=payload)
        assert response.status_code == 201, response.text
        return response.json()

    return create


@pytest.fixture
def create_health_log(
    client: TestClient,
    auth_as: Callable[[UserRole], User],
) -> Callable[..., dict[str, Any]]:
    def create(
        tree_id: int,
        role: UserRole = UserRole.admin,
        **overrides: Any,
    ) -> dict[str, Any]:
        auth_as(role)
        payload = {
            "tree_id": tree_id,
            "condition": "Fair",
            "assessed_date": "2026-10-05",
            **overrides,
        }
        response = client.post("/api/health-logs/", json=payload)
        assert response.status_code == 201, response.text
        return response.json()

    return create
