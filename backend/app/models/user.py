from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum, Date
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base
import enum


class UserRole(str, enum.Enum):
    admin = "admin"
    field_worker = "field_worker"
    citizen = "citizen"


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(120), nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    role = Column(Enum(UserRole), default=UserRole.field_worker, nullable=False)
    subscription_plan = Column(String(20), default="free", nullable=False)
    upgrade_requested = Column(Boolean, default=False, nullable=False)
    ai_identifications_today = Column(Integer, default=0, nullable=False)
    unknown_submissions_today = Column(Integer, default=0, nullable=False)
    ai_usage_date = Column(Date, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    trees = relationship("Tree", back_populates="recorded_by", foreign_keys="Tree.recorded_by_id")
    health_logs = relationship("HealthLog", back_populates="assessor")
