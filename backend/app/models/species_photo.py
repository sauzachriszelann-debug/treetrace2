from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.sql import func

from app.db.database import Base


class SpeciesPhoto(Base):
    """Staff-verified photo reused by every planting suggestion for a species."""

    __tablename__ = "species_photos"

    species_key = Column(String(180), primary_key=True)
    species_name = Column(String(150), nullable=False)
    scientific_name = Column(String(150), nullable=False)
    photo_url = Column(String(500), nullable=False)
    verified_by_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
