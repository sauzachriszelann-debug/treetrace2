from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.models.user import User
from app.core.security import get_current_user
from app.core.config import settings
from supabase import create_client, Client
import uuid
import io

router = APIRouter()


def get_supabase() -> Client:
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_ROLE_KEY:
        raise HTTPException(
            status_code=500,
            detail="Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.",
        )
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)


@router.post("/upload-photo")
async def upload_photo(
    file: UploadFile = File(...),
    _: User = Depends(get_current_user),
):
    """
    Upload a tree photo to Supabase storage.
    Returns the public URL of the uploaded image.
    """
    supabase = get_supabase()

    # Validate content type
    allowed_types = {"image/jpeg", "image/png", "image/webp", "image/gif"}
    if file.content_type not in allowed_types:
        raise HTTPException(status_code=400, detail="File must be a JPEG, PNG, or WebP image")

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else "jpg"
    unique_name = f"{uuid.uuid4()}.{ext}"

    contents = await file.read()
    supabase.storage.from_(settings.SUPABASE_BUCKET_PHOTOS).upload(
        path=unique_name,
        file=contents,
        file_options={"content-type": file.content_type},
    )

    public_url = (
        supabase.storage.from_(settings.SUPABASE_BUCKET_PHOTOS)
        .get_public_url(unique_name)
    )
    return {"file_url": public_url, "path": unique_name}


@router.post("/upload-qr")
async def upload_qr(
    file: UploadFile = File(...),
    _: User = Depends(get_current_user),
):
    """
    Upload a QR code PNG to Supabase storage.
    Returns the public URL.
    """
    supabase = get_supabase()

    unique_name = f"qr-{uuid.uuid4()}.png"
    contents = await file.read()
    supabase.storage.from_(settings.SUPABASE_BUCKET_QR).upload(
        path=unique_name,
        file=contents,
        file_options={"content-type": "image/png"},
    )

    public_url = (
        supabase.storage.from_(settings.SUPABASE_BUCKET_QR)
        .get_public_url(unique_name)
    )
    return {"file_url": public_url, "path": unique_name}


@router.delete("/delete-photo")
def delete_photo(
    path: str,
    _: User = Depends(get_current_user),
):
    """Delete a photo from Supabase storage by its path."""
    supabase = get_supabase()
    supabase.storage.from_(settings.SUPABASE_BUCKET_PHOTOS).remove([path])
    return {"message": "Deleted"}
