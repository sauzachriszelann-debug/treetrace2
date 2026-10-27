"""Phase 13 automated coverage for the AI identification pipeline.

Every test is hermetic: httpx.AsyncClient is replaced with an in-process fake,
so PlantNet, Gemini, GBIF and every other host are never contacted and no API
key is ever used. Synthetic payloads mirror the official response shapes
(PlantNet v2 and Gemini generateContent) with invented species data only.

Covered (Phase 13.6 checklist):
  * Gemini success parsing
  * Gemini retired-model 404 -> fallback model retry (13.1)
  * Gemini exhausted / quota-no-retry / transport error handling (13.1)
  * PlantNet request format + response parsing + fallback behaviour (13.5)
  * Pipeline merge: PlantNet fallback when Gemini fails, and the exact
    on-device failure shape when both fail ("AI error: Gemini 404")
  * Local classifier: not-ready status without model files, route short-circuit
    when ready, graceful fallthrough when classification raises (13.2)
  * API responses: /api/ai/usage shape for citizen vs staff, auth required,
    non-image rejection, daily-limit 402, identify happy path + route-level
    error capture
"""

import asyncio
import json
from datetime import date
from io import BytesIO

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.routes import identify
from app.core.security import get_current_user
from app.db.database import Base, get_db
from app.models.user import User, UserRole
from app.services import ai_identify, species_db
from app.services import local_species_classifier as lsc

# ─────────────────────────────────────────────────────────────────────────────
# Fakes
# ─────────────────────────────────────────────────────────────────────────────

GEMINI_OK_TEXT = json.dumps(
    {
        "common_name": "Narra",
        "scientific_name": "Pterocarpus indicus",
        "family": "Fabaceae",
        "confidence": "High",
        "description": "Synthetic unit-test description.",
        "estimated_dbh_cm": 30,
        "estimated_height_m": 12,
        "dbh_method": "synthetic",
        "distinguishing_features": "synthetic",
        "look_alikes": "synthetic",
        "habitat": "synthetic",
        "uses": "synthetic",
        "is_tree": True,
        "not_identified": False,
    }
)

GEMINI_OK_PAYLOAD = {
    "candidates": [
        {"content": {"parts": [{"text": GEMINI_OK_TEXT}]}}
    ]
}

PLANTNET_OK_PAYLOAD = {
    "results": [
        {
            "score": 0.82,
            "species": {
                "scientificNameWithoutAuthor": "Pterocarpus indicus",
                "commonNames": ["Narra"],
                "family": {"scientificNameWithoutAuthor": "Fabaceae"},
            },
            "images": [
                {"url": {"m": "https://images.example.test/m.jpg"}},
                {"url": {}},
            ],
        }
    ],
    "bestMatch": "Pterocarpus indicus",
}


class FakeResponse:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload if payload is not None else {}

    def json(self):
        return self._payload


def fake_async_client(responder, calls):
    """A stand-in for httpx.AsyncClient that records URLs and never I/Os."""

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

        async def post(self, url, **kwargs):
            calls.append(url)
            out = responder(url, kwargs)
            if isinstance(out, Exception):
                raise out
            return out

        async def get(self, url, **kwargs):
            calls.append(url)
            out = responder(url, kwargs)
            if isinstance(out, Exception):
                raise out
            return out

    return _Client


def run(coro):
    return asyncio.run(coro)


@pytest.fixture(autouse=True)
def _hermetic_ai_keys(monkeypatch):
    # Explicitly non-real placeholder values; the fake transport makes sure
    # they can never leave the process.
    monkeypatch.setattr(ai_identify, "GEMINI_API_KEY", "unit-test-placeholder")
    monkeypatch.setattr(ai_identify, "PLANTNET_API_KEY", "unit-test-placeholder")


# ─────────────────────────────────────────────────────────────────────────────
# 13.1 — Gemini model handling
# ─────────────────────────────────────────────────────────────────────────────

def test_gemini_parses_success(monkeypatch):
    calls = []

    def responder(url, kwargs):
        assert "gemini-3.5-flash-lite" in url  # primary model in use
        return FakeResponse(200, GEMINI_OK_PAYLOAD)

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, calls))

    out = run(ai_identify._gemini("aW1n", "image/png", hint=None))
    assert out["not_identified"] is False
    assert out["common_name"] == "Narra"
    assert out["confidence"] == "High"
    assert out["estimated_dbh_cm"] == 30
    assert len(calls) == 1


def test_gemini_falls_back_when_primary_model_retired(monkeypatch):
    """404 on the primary (retired) model must retry the fallback model."""
    calls = []

    def responder(url, kwargs):
        if "gemini-3.5-flash-lite" in url:
            return FakeResponse(404, {"error": {"message": "not found"}})
        assert "gemini-3.1-flash-lite" in url
        return FakeResponse(200, GEMINI_OK_PAYLOAD)

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, calls))

    out = run(ai_identify._gemini("aW1n", "image/png", hint=None))
    assert out["not_identified"] is False
    assert out["common_name"] == "Narra"
    assert len(calls) == 2, "expected primary then fallback attempt"


def test_gemini_exhausted_models_reports_status(monkeypatch):
    calls = []

    def responder(url, kwargs):
        return FakeResponse(404, {"error": {"message": "model retired"}})

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, calls))

    out = run(ai_identify._gemini("aW1n", "image/png", hint=None))
    assert out["not_identified"] is True
    # Same reason shape the app renders on device ("AI error: Gemini <code>").
    assert "AI error: Gemini 404" in out["reason"]
    assert "gemini-3.5-flash-lite" in out["reason"]
    assert "gemini-3.1-flash-lite" in out["reason"]
    assert len(calls) == 2


def test_gemini_quota_error_is_not_retried(monkeypatch):
    """429 is project-wide: a second model would hit the same quota."""
    calls = []

    def responder(url, kwargs):
        return FakeResponse(429, {"error": {"message": "quota"}})

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, calls))

    out = run(ai_identify._gemini("aW1n", "image/png", hint=None))
    assert out["not_identified"] is True
    assert "Gemini 429" in out["reason"]
    assert len(calls) == 1, "quota errors must not trigger model fallback"


def test_gemini_transport_error_is_graceful(monkeypatch):
    import httpx as real_httpx

    def responder(url, kwargs):
        raise real_httpx.ConnectError("simulated outage")

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, []))

    out = run(ai_identify._gemini("aW1n", "image/png", hint=None))
    assert out["not_identified"] is True
    assert out["reason"].startswith("AI error:")


def test_species_db_uses_configured_model_not_retired_one():
    assert "gemini-2.0-flash-lite" not in species_db.GEMINI_MODEL
    assert species_db.GEMINI_MODEL.startswith("gemini-")


# ─────────────────────────────────────────────────────────────────────────────
# 13.5 — PlantNet integration (mocked)
# ─────────────────────────────────────────────────────────────────────────────

def test_plantnet_request_format_and_parsing(monkeypatch):
    calls = []

    def responder(url, kwargs):
        assert url == ai_identify.PLANTNET_URL
        # Official contract: api-key query param + multipart "images" field.
        assert "api-key" in kwargs.get("params", {})
        files = kwargs.get("files", {})
        assert "images" in files
        return FakeResponse(200, PLANTNET_OK_PAYLOAD)

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, calls))

    out = run(ai_identify._plantnet(b"fake-image-bytes", "image/jpeg"))
    assert out is not None
    assert out["common_name"] == "Narra"
    assert out["scientific_name"] == "Pterocarpus indicus"
    assert out["family"] == "Fabaceae"
    assert out["confidence"] == "High"  # score 0.82 > 0.55
    assert out["plantnet_score"] == 0.82
    assert out["source"] == "plantnet"
    assert out["match_images"] == ["https://images.example.test/m.jpg"]


def test_plantnet_invalid_key_returns_none(monkeypatch):
    def responder(url, kwargs):
        return FakeResponse(401, {"error": "unauthorized"})

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, []))

    assert run(ai_identify._plantnet(b"x", "image/jpeg")) is None


def test_plantnet_low_score_returns_none(monkeypatch):
    payload = json.loads(json.dumps(PLANTNET_OK_PAYLOAD))
    payload["results"][0]["score"] = 0.01

    def responder(url, kwargs):
        return FakeResponse(200, payload)

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, []))

    assert run(ai_identify._plantnet(b"x", "image/jpeg")) is None


# ─────────────────────────────────────────────────────────────────────────────
# Pipeline merge behaviour (PlantNet fallback / both-down failure shape)
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def pipeline_env(monkeypatch):
    """Neutralise GBIF + async species check so only PlantNet/Gemini matter."""
    async def _no_gbif(name):
        return None

    async def _no_auto_check(common, sci):
        return {
            "status": "Not Listed",
            "status_code": "NL",
            "iucn_color": "#9e9e9e",
            "cutting_allowed": True,
            "protected": False,
            "source": "default",
        }

    monkeypatch.setattr(ai_identify, "_gbif_match", _no_gbif)
    monkeypatch.setattr(species_db, "auto_check_species", _no_auto_check)


def test_pipeline_plantnet_fallback_when_gemini_retired(pipeline_env, monkeypatch):
    calls = []

    def responder(url, kwargs):
        if "plantnet" in url:
            return FakeResponse(200, PLANTNET_OK_PAYLOAD)
        return FakeResponse(404, {"error": {"message": "model retired"}})

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, calls))

    out = run(ai_identify._pipeline_with_status(b"img", "aW1n", "image/jpeg"))
    # PlantNet carried the identification after Gemini failed — the graceful
    # degradation verified live in Phase 13.
    assert out["not_identified"] is False
    assert out["common_name"] == "Narra"
    assert out["fallback"] is True
    assert "Gemini 404" in out["fallback_reason"]


def test_pipeline_both_down_returns_device_failure_shape(pipeline_env, monkeypatch):
    def responder(url, kwargs):
        if "plantnet" in url:
            import httpx as real_httpx
            raise real_httpx.ConnectError("simulated plantnet outage")
        return FakeResponse(404, {"error": {"message": "model retired"}})

    monkeypatch.setattr(ai_identify.httpx, "AsyncClient", fake_async_client(responder, []))

    out = run(ai_identify._pipeline_with_status(b"img", "aW1n", "image/jpeg"))
    # Exact shape the device showed on 2026-10-25 before the fix.
    assert out["not_identified"] is True
    assert out["partial"] is True
    assert "AI error: Gemini 404" in out["reason"]


# ─────────────────────────────────────────────────────────────────────────────
# 13.2 — Local classifier behaviour
# ─────────────────────────────────────────────────────────────────────────────

def test_local_status_not_ready_without_model_files(monkeypatch, tmp_path):
    monkeypatch.setattr(lsc, "TFLITE_MODEL_PATH", tmp_path / "best_model.tflite")
    monkeypatch.setattr(lsc, "LABELS_PATH", tmp_path / "labels.txt")

    status = lsc.local_species_model_status()
    assert status["ready"] is False
    assert status["model_found"] is False
    assert status["labels_found"] is False
    assert "best_model.tflite" in status["how_to_enable"]
    assert "labels.txt" in status["how_to_enable"]


# ─────────────────────────────────────────────────────────────────────────────
# API-level responses (own app fixture — conftest's api_app has no identify)
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def ai_client(db_session):
    app = FastAPI()
    app.include_router(identify.router, prefix="/api/ai")

    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        yield client, app, db_session


def _make_user(db, role, **kwargs):
    user = User(
        full_name=f"p13 {role.value}",
        email=f"p13-{role.value}-{db.query(User).count()}@example.test",
        hashed_password="unit-test-hash",
        role=role,
        is_active=True,
        **kwargs,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _auth_override(app, user):
    app.dependency_overrides[get_current_user] = lambda: user


def test_usage_endpoint_citizen_shape(ai_client):
    client, app, db = ai_client
    user = _make_user(db, UserRole.citizen)
    _auth_override(app, user)

    res = client.get("/api/ai/usage")
    assert res.status_code == 200
    body = res.json()
    assert set(body) >= {"ai", "unknown", "tree_submissions", "qr_scan", "public_map"}
    assert body["ai"]["unlimited"] is False
    assert body["ai"]["daily_limit"] == 10
    assert body["ai"]["remaining"] == 10
    # The Flutter parser reads these exact keys.
    assert set(body["ai"]) >= {"used_today", "daily_limit", "remaining", "unlimited", "plan"}


def test_usage_endpoint_staff_unlimited(ai_client):
    client, app, db = ai_client
    user = _make_user(db, UserRole.field_worker)
    _auth_override(app, user)

    body = client.get("/api/ai/usage").json()
    assert body["ai"]["unlimited"] is True
    assert body["ai"]["plan"] == "staff"


def test_usage_requires_auth(ai_client):
    client, _, _ = ai_client
    res = client.get("/api/ai/usage")
    assert res.status_code == 401


def test_identify_requires_auth(ai_client):
    client, _, _ = ai_client
    res = client.post(
        "/api/ai/identify",
        files={"file": ("leaf.png", b"\x89PNG fake", "image/png")},
    )
    assert res.status_code == 401


def test_identify_rejects_non_image(ai_client):
    client, app, db = ai_client
    user = _make_user(db, UserRole.field_worker)
    _auth_override(app, user)

    res = client.post(
        "/api/ai/identify",
        files={"file": ("notes.txt", b"not an image", "text/plain")},
    )
    assert res.status_code == 400
    assert "image" in res.json()["detail"].lower()


def test_identify_enforces_daily_limit_for_citizen(ai_client):
    client, app, db = ai_client
    user = _make_user(
        db,
        UserRole.citizen,
        ai_usage_date=date.today(),
        ai_identifications_today=10,
    )
    _auth_override(app, user)

    res = client.post(
        "/api/ai/identify",
        files={"file": ("leaf.png", b"\x89PNG fake", "image/png")},
    )
    assert res.status_code == 402
    assert "10" in res.json()["detail"]


def test_identify_happy_path_uses_pipeline(ai_client, monkeypatch):
    client, app, db = ai_client
    user = _make_user(db, UserRole.field_worker)
    _auth_override(app, user)

    fixture = {
        "common_name": "Synthetic Fir",
        "scientific_name": "Picea ficta",
        "confidence": "High",
        "not_identified": False,
        "source": "unit-test",
    }
    called = []

    async def fake_pipeline(image_bytes, image_b64, content_type):
        called.append((image_bytes, image_b64, content_type))
        return dict(fixture)

    monkeypatch.setattr(identify, "_pipeline_with_status", fake_pipeline)

    res = client.post(
        "/api/ai/identify",
        files={"file": ("leaf.png", b"\x89PNG fake", "image/png")},
    )
    assert res.status_code == 200
    assert res.json() == fixture
    assert len(called) == 1


def test_identify_route_captures_pipeline_exception(ai_client, monkeypatch):
    """A pipeline explosion still answers 200 with the safe fallback body."""
    client, app, db = ai_client
    user = _make_user(db, UserRole.field_worker)
    _auth_override(app, user)

    async def exploding_pipeline(*args, **kwargs):
        raise RuntimeError("synthetic pipeline explosion")

    monkeypatch.setattr(identify, "_pipeline_with_status", exploding_pipeline)

    res = client.post(
        "/api/ai/identify",
        files={"file": ("leaf.png", b"\x89PNG fake", "image/png")},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["not_identified"] is True
    assert "debug_detail" in body
    assert "synthetic pipeline explosion" in body["debug_detail"]


def test_identify_uses_local_classifier_when_ready(ai_client, monkeypatch):
    client, app, db = ai_client
    user = _make_user(db, UserRole.field_worker)
    _auth_override(app, user)

    local_result = {"common_name": "Local Class", "not_identified": False, "source": "local"}
    pipeline_called = []

    async def fake_pipeline(*args, **kwargs):
        pipeline_called.append(True)
        return {}

    def ready():
        return (lambda _b: dict(local_result), lambda: {"ready": True})

    monkeypatch.setattr(identify, "_get_local_species_classifier", ready)
    monkeypatch.setattr(identify, "_pipeline_with_status", fake_pipeline)

    res = client.post(
        "/api/ai/identify",
        files={"file": ("leaf.png", b"\x89PNG fake", "image/png")},
    )
    assert res.status_code == 200
    assert res.json()["source"] == "local"
    assert pipeline_called == [], "ready local model must short-circuit the pipeline"


def test_identify_falls_through_when_local_classifier_raises(ai_client, monkeypatch):
    client, app, db = ai_client
    user = _make_user(db, UserRole.field_worker)
    _auth_override(app, user)

    pipeline_called = []

    async def fake_pipeline(*args, **kwargs):
        pipeline_called.append(True)
        return {"common_name": "Pipeline Wins", "not_identified": False}

    def ready_but_broken():
        def _boom(_b):
            raise RuntimeError("local inference failed")

        return (_boom, lambda: {"ready": True})

    monkeypatch.setattr(identify, "_get_local_species_classifier", ready_but_broken)
    monkeypatch.setattr(identify, "_pipeline_with_status", fake_pipeline)

    res = client.post(
        "/api/ai/identify",
        files={"file": ("leaf.png", b"\x89PNG fake", "image/png")},
    )
    assert res.status_code == 200
    assert res.json()["common_name"] == "Pipeline Wins"
    assert pipeline_called == [True]
