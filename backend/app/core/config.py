from typing import Optional

from pydantic import model_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # App
    APP_NAME: str = "TreeTrace"
    # Runtime secrets must come from the environment. TESTING is only for the
    # isolated in-memory test suite and must never be enabled in deployment.
    TESTING: bool = False
    SECRET_KEY: Optional[str] = None
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # Frontend URL (used in email links)
    FRONTEND_URL: str = "http://localhost:5173"

    # Database
    DATABASE_URL: str = ""

    # This validator ensures 'postgres://' is changed to 'postgresql://'
    # and handles Aiven's specific needs if necessary.
    @property
    def SQLALCHEMY_DATABASE_URL(self) -> str:
        if self.DATABASE_URL.startswith("postgres://"):
            return self.DATABASE_URL.replace("postgres://", "postgresql://", 1)
        return self.DATABASE_URL


    # Supabase — file storage only
    SUPABASE_URL: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""
    SUPABASE_BUCKET_PHOTOS: str = "tree-photos"
    SUPABASE_BUCKET_QR: str = "qr-codes"

    GMAIL_USER: str = ""
    GMAIL_APP_PASSWORD: str = ""
    GEMINI_API_KEY: str = ""

    #API identification
    PERENUAL_API_KEY: str = ""
    TREFLE_API_KEY: str = ""


    # Anthropic — AI identification
    ANTHROPIC_API_KEY: str = ""

    # Optional local YOLO segmentation for DBH estimation
    ENABLE_YOLO_DBH: bool = False

    # Pl@ntNet — provided by the environment when enabled.
    PLANTNET_API_KEY: str = ""

    # Resend — transactional email (free: 3,000/month)
    # Sign up at https://resend.com → API Keys → Create Key
    RESEND_API_KEY: str = ""
    # Must be a verified sender domain in Resend (or use onboarding@resend.dev for testing)
    EMAIL_FROM: str = "TreeTrace <onboarding@resend.dev>"
    EMAIL_FROM_NAME: str = "TreeTrace"

    @model_validator(mode="after")
    def require_secret_key_outside_tests(self) -> "Settings":
        if not self.TESTING and not self.SECRET_KEY:
            raise ValueError("SECRET_KEY must be set in the environment.")
        return self

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
