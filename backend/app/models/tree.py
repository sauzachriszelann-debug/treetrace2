from sqlalchemy import (
    Column, Integer, String, Float, Date, Text,
    DateTime, ForeignKey, Enum, UniqueConstraint
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

    # The G2 idempotency key has exactly ONE uniqueness object, named to
    # match backend/migrations/0001_add_trees_client_uuid.sql: on
    # PostgreSQL a named UNIQUE constraint creates an index called
    # ux_trees_client_uuid, the same name the migration creates, so
    # create_all and the versioned migration converge instead of stacking
    # a second (redundant) index.
    __table_args__ = (
        UniqueConstraint("client_uuid", name="ux_trees_client_uuid"),
    )

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

    # Idempotency key supplied by clients (G2); NULL for legacy clients.
    # Uniqueness comes from the named constraint above - do NOT add
    # unique=True/index=True here, that would create redundant indexes.
    client_uuid = Column(String(36), nullable=True)

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

    def _conservation_info(self):
        from app.services.species_db import lookup_species

        return (
            lookup_species(self.common_name or "")
            or lookup_species(self.scientific_name or "")
            or {}
        )

    @property
    def endangered_status(self):
        return self._conservation_info().get("status", "Not Listed")

    @property
    def status_code(self):
        return self._conservation_info().get("status_code", "NL")

    @property
    def protected(self):
        return bool(self._conservation_info().get("protected", False))

    @property
    def cutting_allowed(self):
        return bool(self._conservation_info().get("cutting_allowed", True))
