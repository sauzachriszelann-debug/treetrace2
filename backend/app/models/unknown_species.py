from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base


class UnknownSpecies(Base):
    __tablename__ = "unknown_species"

    id = Column(Integer, primary_key=True, index=True)
    photo_url = Column(String(500), nullable=False)
    location_description = Column(String(255), nullable=True)
    barangay = Column(String(120), nullable=True)
    submitter_notes = Column(Text, nullable=True)
    possible_name = Column(String(150), nullable=True)   # user's guess
    ai_candidates = Column(Text, nullable=True)           # JSON list from AI
    reviewed = Column(Boolean, default=False)
    review_notes = Column(Text, nullable=True)
    identified_as = Column(String(150), nullable=True)    # admin fills after review

    submitted_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    submitted_by = relationship("User", foreign_keys=[submitted_by_id])

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
