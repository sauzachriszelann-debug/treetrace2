from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # App
    APP_NAME: str = "TreeTrace"
    SECRET_KEY: str = "change-me-in-production-use-a-long-random-string"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # Frontend URL (used in email links)
    FRONTEND_URL: str = "http://localhost:5173"

    # Database — MySQL
    #DATABASE_URL: str = "mysql+pymysql://root:password@localhost:3306/treetrace"

    #Database - Aiven
    #DATABASE_URL: str = ""

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

    # Pl@ntNet — Free botanical identification API (500 req/day free)
    PLANTNET_API_KEY: str = "2b10i4RHoL4hnlBaJ6f7jyVb"

    # Resend — transactional email (free: 3,000/month)
    # Sign up at https://resend.com → API Keys → Create Key
    RESEND_API_KEY: str = ""
    # Must be a verified sender domain in Resend (or use onboarding@resend.dev for testing)
    EMAIL_FROM: str = "TreeTrace <onboarding@resend.dev>"
    EMAIL_FROM_NAME: str = "TreeTrace"

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
