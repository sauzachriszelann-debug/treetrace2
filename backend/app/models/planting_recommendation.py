from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base


class PlantingRecommendation(Base):
    __tablename__ = "planting_recommendations"

    id = Column(Integer, primary_key=True, index=True)
    species_name = Column(String(150), nullable=False)
    scientific_name = Column(String(150), nullable=True)
    barangay = Column(String(120), nullable=True)
    reason = Column(Text, nullable=True)
    photo_url = Column(String(500), nullable=True)
    status = Column(String(40), nullable=False, default="recommended")
    planted = Column(Boolean, nullable=False, default=False)

    submitted_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    submitted_by = relationship("User", foreign_keys=[submitted_by_id])

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
