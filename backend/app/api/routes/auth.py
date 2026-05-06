from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.db.database import get_db
from app.schemas.auth import RegisterRequest, LoginRequest, TokenResponse, UserOut
from app.models.user import User, UserRole
from app.core.security import (
    hash_password, verify_password, create_access_token, get_current_user
)

router = APIRouter()


def _role_value(role: UserRole | str) -> str:
    return role.value if isinstance(role, UserRole) else str(role).split(".")[-1]


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    """Public self-registration — citizen role only."""
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )
    # Block self-registration as admin or field_worker
    if payload.role in ("admin", "field_worker"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin and Field Worker accounts must be created by an administrator.",
        )
    user = User(
        full_name=payload.full_name,
        email=payload.email,
        hashed_password=hash_password(payload.password),
        role=UserRole.citizen,  # always citizen for self-registration
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token({
        "sub": str(user.id),
        "role": _role_value(user.role),
    })
    return {"access_token": token, "token_type": "bearer"}


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    """Authenticate user and return a JWT."""
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )
    token = create_access_token({
        "sub": str(user.id),
        "role": _role_value(user.role),
    })
    return {"access_token": token, "token_type": "bearer"}


@router.get("/me", response_model=UserOut)
def me(current_user: User = Depends(get_current_user)):
    """Return the currently authenticated user's profile."""
    return current_user
