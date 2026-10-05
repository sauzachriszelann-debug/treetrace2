from io import BytesIO
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.api.routes import storage
from app.core.security import get_current_user
from app.models.user import UserRole


class FakeBucket:
    def __init__(self, client, bucket: str):
        self.client = client
        self.bucket = bucket

    def upload(self, *, path: str, file: bytes, file_options: dict):
        self.client.uploads.append((self.bucket, path, file, file_options))

    def get_public_url(self, path: str) -> str:
        return f"https://storage.example.test/{self.bucket}/{path}"

    def remove(self, paths: list[str]):
        self.client.removals.append((self.bucket, paths))


class FakeStorage:
    def __init__(self, client):
        self.client = client

    def from_(self, bucket: str) -> FakeBucket:
        return FakeBucket(self.client, bucket)


class FakeSupabase:
    def __init__(self):
        self.storage = FakeStorage(self)
        self.uploads: list[tuple[str, str, bytes, dict]] = []
        self.removals: list[tuple[str, list[str]]] = []


@pytest.fixture
def fake_supabase(monkeypatch) -> FakeSupabase:
    fake = FakeSupabase()
    monkeypatch.setattr(storage, "get_supabase", lambda: fake)
    return fake


@pytest.fixture
def png_bytes() -> bytes:
    image = Image.new("RGB", (8, 8), color="green")
    contents = BytesIO()
    image.save(contents, format="PNG")
    return contents.getvalue()


def upload(client: TestClient, contents: bytes, purpose: str, mime: str = "image/png"):
    return client.post(
        "/api/storage/upload-photo",
        data={"purpose": purpose},
        files={"file": ("image.png", contents, mime)},
    )


def test_unauthenticated_upload_is_rejected(client, png_bytes):
    response = upload(client, png_bytes, "tree_photo")
    assert response.status_code == 401


def test_citizen_cannot_upload_tree_photo(client, auth_as, fake_supabase, png_bytes):
    auth_as(UserRole.citizen)
    response = upload(client, png_bytes, "tree_photo")
    assert response.status_code == 403
    assert fake_supabase.uploads == []


@pytest.mark.parametrize("role", [UserRole.admin, UserRole.field_worker])
def test_staff_can_upload_tree_photo(client, auth_as, fake_supabase, png_bytes, role):
    user = auth_as(role)
    response = upload(client, png_bytes, "tree_photo")
    assert response.status_code == 200
    path = response.json()["path"]
    assert path.startswith(f"trees/{user.id}/")
    assert fake_supabase.uploads[0][0] == "tree-photos"


@pytest.mark.parametrize("role", [UserRole.citizen, UserRole.field_worker])
def test_non_admin_cannot_upload_qr(client, auth_as, fake_supabase, png_bytes, role):
    auth_as(role)
    response = client.post(
        "/api/storage/upload-qr",
        files={"file": ("qr.png", png_bytes, "image/png")},
    )
    assert response.status_code == 403
    assert fake_supabase.uploads == []


def test_admin_can_upload_qr(client, admin_user, fake_supabase, png_bytes):
    response = client.post(
        "/api/storage/upload-qr",
        files={"file": ("qr.png", png_bytes, "image/png")},
    )
    assert response.status_code == 200
    assert response.json()["path"].startswith("qr/")
    assert fake_supabase.uploads[0][0] == "qr-codes"


@pytest.mark.parametrize("purpose", ["unknown_species", "planting_submission"])
def test_citizen_can_upload_submission_images(
    client, citizen_user, fake_supabase, png_bytes, purpose
):
    response = upload(client, png_bytes, purpose)
    assert response.status_code == 200
    assert response.json()["path"].startswith(f"submissions/{citizen_user.id}/{purpose}/")


@pytest.mark.parametrize("role", [UserRole.citizen, UserRole.field_worker])
def test_non_admin_cannot_delete_photo(client, auth_as, fake_supabase, role):
    auth_as(role)
    response = client.delete(
        "/api/storage/delete-photo",
        params={"path": f"trees/1/{uuid4()}.png"},
    )
    assert response.status_code == 403
    assert fake_supabase.removals == []


def test_admin_can_delete_only_permitted_photo_paths(client, admin_user, fake_supabase):
    valid_path = f"trees/2/{uuid4()}.png"
    response = client.delete("/api/storage/delete-photo", params={"path": valid_path})
    assert response.status_code == 200
    assert fake_supabase.removals == [("tree-photos", [valid_path])]

    invalid = client.delete("/api/storage/delete-photo", params={"path": "../other-user.png"})
    assert invalid.status_code == 400


def test_oversized_photo_is_rejected(client, admin_user, fake_supabase, png_bytes, monkeypatch):
    monkeypatch.setattr(storage, "MAX_PHOTO_BYTES", len(png_bytes) - 1)
    response = upload(client, png_bytes, "tree_photo")
    assert response.status_code == 413
    assert fake_supabase.uploads == []


def test_spoofed_or_invalid_image_is_rejected(client, admin_user, fake_supabase):
    response = upload(client, b"not an image", "tree_photo")
    assert response.status_code == 400
    assert fake_supabase.uploads == []


def test_invalid_qr_bytes_are_rejected(client, admin_user, fake_supabase):
    response = client.post(
        "/api/storage/upload-qr",
        files={"file": ("qr.png", b"not a png", "image/png")},
    )
    assert response.status_code == 400
    assert fake_supabase.uploads == []


def test_public_tree_keeps_existing_media_urls(client, create_tree):
    tree = create_tree(
        photo_url="https://storage.example.test/tree-photos/trees/1/photo.png",
        qr_code_url="https://storage.example.test/qr-codes/qr/code.png",
    )
    client.app.dependency_overrides.pop(get_current_user, None)

    response = client.get(f"/api/public/tree/{tree['id']}")
    assert response.status_code == 200
    assert response.json()["photo_url"] == tree["photo_url"]
    assert response.json()["qr_code_url"] == tree["qr_code_url"]
