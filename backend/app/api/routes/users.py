from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List
from app.db.database import get_db
from app.models.user import User, UserRole
from app.schemas.auth import UserOut, UserCreatedOut, InviteRequest
from app.core.security import get_current_user, require_admin, hash_password
from app.services.email_service import send_welcome_email
import secrets
import string

router = APIRouter()


@router.get("", response_model=List[UserOut])
@router.get("/", response_model=List[UserOut], include_in_schema=False)
def list_users(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """List all users. Admin only."""
    return db.query(User).order_by(User.created_at.desc()).all()


@router.post("", response_model=UserCreatedOut, status_code=201)
@router.post("/invite", response_model=UserCreatedOut, status_code=201, include_in_schema=False)
def create_user(
    payload: InviteRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """
    Create a new user. Admin only.
    - If `password` is provided (min 6 chars), it's set directly and NOT emailed
      (admin sets it themselves and shares it manually).
    - If `password` is omitted, a random 12-char password is auto-generated,
      returned in the response AND emailed to the user if Resend is configured.
    """
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email already exists.",
        )

    auto_generated = not (payload.password and len(payload.password) >= 6)

    if auto_generated:
        alphabet       = string.ascii_letters + string.digits + "!@#$"
        plain_password = "".join(secrets.choice(alphabet) for _ in range(12))
        temp_password  = plain_password   # return to admin + email to user
    else:
        plain_password = payload.password
        temp_password  = None             # admin set it manually, don't expose

    role = UserRole.admin if payload.role == "admin" else UserRole.field_worker
    user = User(
        full_name=payload.full_name.strip() or payload.email,
        email=payload.email,
        hashed_password=hash_password(plain_password),
        role=role,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    # Send welcome email in the background (doesn't block the API response)
    if auto_generated:
        background_tasks.add_task(
            send_welcome_email,
            to_email=user.email,
            full_name=user.full_name,
            temp_password=plain_password,
            role=user.role,
        )

    return {
        "id":            user.id,
        "full_name":     user.full_name,
        "email":         user.email,
        "role":          user.role,
        "is_active":     user.is_active,
        "temp_password": temp_password,
    }


@router.put("/{user_id}/role")
def update_role(
    user_id: int,
    role: str,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Update a user's role. Admin only."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.role = UserRole.admin if role == "admin" else UserRole.field_worker
    db.commit()
    return {"message": "Role updated"}


@router.put("/{user_id}/deactivate")
def deactivate_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """Deactivate a user account. Admin only."""
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot deactivate yourself")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = False
    db.commit()
    return {"message": "User deactivated"}


@router.put("/{user_id}/activate")
def activate_user(
    user_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Re-activate a deactivated user. Admin only."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = True
    db.commit()
    return {"message": "User activated"}
