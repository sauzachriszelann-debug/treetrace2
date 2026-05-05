from sqlalchemy import (
    Column, Integer, String, Float, Date, Text,
    DateTime, ForeignKey, Enum
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base
import enum


class HealthStatus(str, enum.Enum):
    Healthy = "Healthy"
    Fair = "Fair"
    Poor = "Poor"


class Tree(Base):
    __tablename__ = "trees"

    id = Column(Integer, primary_key=True, index=True)

    # Species
    common_name = Column(String(150), nullable=False, index=True)
    scientific_name = Column(String(150), nullable=True)

    # Measurements
    dbh_cm = Column(Float, nullable=True)
    height_m = Column(Float, nullable=True)
    biomass_kg = Column(Float, nullable=True)
    carbon_kg = Column(Float, nullable=True)

    # Health
    health_status = Column(Enum(HealthStatus), nullable=False, default=HealthStatus.Healthy)

    # Location
    barangay = Column(String(120), nullable=True)
    city = Column(String(120), nullable=True, default="Panabo City")
    province = Column(String(120), nullable=True, default="Davao del Norte")
    lat = Column(Float, nullable=True)
    lng = Column(Float, nullable=True)

    # Media (Supabase URLs)
    photo_url = Column(String(500), nullable=True)
    qr_code_url = Column(String(500), nullable=True)

    # Record metadata
    date_recorded = Column(Date, nullable=True)
    notes = Column(Text, nullable=True)

    # FK to user
    recorded_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    recorded_by = relationship("User", back_populates="trees", foreign_keys=[recorded_by_id])

    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    health_logs = relationship("HealthLog", back_populates="tree", cascade="all, delete-orphan")
