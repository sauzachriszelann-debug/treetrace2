from sqlalchemy import Column, Integer, String, Float, Date, Text, DateTime, ForeignKey, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base
from app.models.tree import HealthStatus


class HealthLog(Base):
    __tablename__ = "health_logs"

    id = Column(Integer, primary_key=True, index=True)

    # Tree reference
    tree_id = Column(Integer, ForeignKey("trees.id"), nullable=False, index=True)
    tree = relationship("Tree", back_populates="health_logs")

    # Assessment data
    condition = Column(Enum(HealthStatus), nullable=False)
    notes = Column(Text, nullable=True)
    assessed_date = Column(Date, nullable=False)
    dbh_cm = Column(Float, nullable=True)
    height_m = Column(Float, nullable=True)
    photo_url = Column(String(500), nullable=True)

    # Assessor
    assessed_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    assessor = relationship("User", back_populates="health_logs")

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
