import io
import re
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError

from app.core.security import get_current_user, require_admin
from app.core.config import settings
from app.models.user import User, UserRole
from supabase import create_client, Client

router = APIRouter()

UploadPurpose = Literal["tree_photo", "unknown_species", "planting_submission"]

MAX_PHOTO_BYTES = 10 * 1024 * 1024
MAX_QR_BYTES = 2 * 1024 * 1024
MAX_IMAGE_PIXELS = 40_000_000

IMAGE_TYPES = {
    "JPEG": ("image/jpeg", "jpg"),
    "PNG": ("image/png", "png"),
    "WEBP": ("image/webp", "webp"),
    "GIF": ("image/gif", "gif"),
}
LEGACY_PHOTO_PATH = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(?:jpg|png|webp|gif)$",
    re.IGNORECASE,
)
NAMESPACED_PHOTO_PATH = re.compile(
    r"^(?:trees/\d+|submissions/\d+/(?:unknown_species|planting_submission))/"
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    r"\.(?:jpg|png|webp|gif)$",
    re.IGNORECASE,
)


def get_supabase() -> Client:
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise HTTPException(
            status_code=500,
            detail="Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.",
        )
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


def _role_name(user: User) -> str:
    role = user.role
    return role.value if isinstance(role, UserRole) else str(role).split(".")[-1].lower()


def _can_upload(user: User, purpose: UploadPurpose) -> bool:
    role = _role_name(user)
    if purpose == "tree_photo":
        return role in {UserRole.admin.value, UserRole.field_worker.value}
    return role in {
        UserRole.admin.value,
        UserRole.field_worker.value,
        UserRole.citizen.value,
    }


async def _read_limited(file: UploadFile, max_bytes: int) -> bytes:
    contents = bytearray()
    while chunk := await file.read(64 * 1024):
        contents.extend(chunk)
        if len(contents) > max_bytes:
            raise HTTPException(status_code=413, detail="Image exceeds the allowed upload size.")
    if not contents:
        raise HTTPException(status_code=400, detail="Image file is empty.")
    return bytes(contents)


def _validate_image(contents: bytes, content_type: str | None, *, png_only: bool = False) -> str:
    try:
        with Image.open(io.BytesIO(contents)) as image:
            image_format = image.format
            width, height = image.size
            image.verify()
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError):
        raise HTTPException(status_code=400, detail="Uploaded file is not a valid image.")

    if width * height > MAX_IMAGE_PIXELS:
        raise HTTPException(status_code=413, detail="Image dimensions exceed the allowed limit.")
    if image_format not in IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported image format.")

    expected_content_type, extension = IMAGE_TYPES[image_format]
    if content_type != expected_content_type:
        raise HTTPException(status_code=400, detail="Image MIME type does not match its file content.")
    if png_only and image_format != "PNG":
        raise HTTPException(status_code=400, detail="QR uploads must be valid PNG images.")
    return extension


def _photo_path(purpose: UploadPurpose, user: User, extension: str) -> str:
    identifier = uuid.uuid4()
    if purpose == "tree_photo":
        return f"trees/{user.id}/{identifier}.{extension}"
    return f"submissions/{user.id}/{purpose}/{identifier}.{extension}"


def _is_permitted_photo_path(path: str) -> bool:
    return bool(LEGACY_PHOTO_PATH.fullmatch(path) or NAMESPACED_PHOTO_PATH.fullmatch(path))


@router.post("/upload-photo")
async def upload_photo(
    file: UploadFile = File(...),
    purpose: UploadPurpose = Form(...),
    current_user: User = Depends(get_current_user),
):
    """
    Upload a tree photo to Supabase storage.
    Returns the public URL of the uploaded image.
    """
    if not _can_upload(current_user, purpose):
        raise HTTPException(status_code=403, detail="Your role cannot upload this type of image.")

    contents = await _read_limited(file, MAX_PHOTO_BYTES)
    extension = _validate_image(contents, file.content_type)
    path = _photo_path(purpose, current_user, extension)
    supabase = get_supabase()
    supabase.storage.from_(settings.SUPABASE_BUCKET_PHOTOS).upload(
        path=path,
        file=contents,
        file_options={"content-type": file.content_type},
    )

    public_url = (
        supabase.storage.from_(settings.SUPABASE_BUCKET_PHOTOS)
        .get_public_url(path)
    )
    return {"file_url": public_url, "path": path}


@router.post("/upload-qr")
async def upload_qr(
    file: UploadFile = File(...),
    _: User = Depends(require_admin),
):
    """
    Upload a QR code PNG to Supabase storage.
    Returns the public URL.
    """
    contents = await _read_limited(file, MAX_QR_BYTES)
    _validate_image(contents, file.content_type, png_only=True)
    path = f"qr/{uuid.uuid4()}.png"
    supabase = get_supabase()
    supabase.storage.from_(settings.SUPABASE_BUCKET_QR).upload(
        path=path,
        file=contents,
        file_options={"content-type": "image/png"},
    )

    public_url = (
        supabase.storage.from_(settings.SUPABASE_BUCKET_QR)
        .get_public_url(path)
    )
    return {"file_url": public_url, "path": path}


@router.delete("/delete-photo")
def delete_photo(
    path: str,
    _: User = Depends(require_admin),
):
    """Delete a photo from Supabase storage by its path."""
    if not _is_permitted_photo_path(path):
        raise HTTPException(status_code=400, detail="Invalid TreeTrace photo path.")
    supabase = get_supabase()
    supabase.storage.from_(settings.SUPABASE_BUCKET_PHOTOS).remove([path])
    return {"message": "Deleted"}
