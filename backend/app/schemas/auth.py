from pydantic import BaseModel, EmailStr
from typing import Optional


class RegisterRequest(BaseModel):
    full_name: str
    email: EmailStr
    password: str
    role: str = "citizen"


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    full_name: str
    email: str
    role: str
    is_active: bool

    class Config:
        from_attributes = True


class UserCreatedOut(UserOut):
    """Returned only on creation — includes the temporary password so admin can share it."""
    temp_password: Optional[str] = None


class InviteRequest(BaseModel):
    email: EmailStr
    role: str = "field_worker"
    full_name: str = ""
    password: Optional[str] = None   # If omitted, a random one is generated
