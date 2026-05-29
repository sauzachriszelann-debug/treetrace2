from sqlalchemy import Boolean, Column, DateTime, Float, Integer, String
from sqlalchemy.sql import func

from app.db.database import Base


class EvaluationTestResult(Base):
    __tablename__ = "evaluation_test_results"

    id = Column(Integer, primary_key=True, index=True)
    image_id = Column(String(120), nullable=False, index=True)
    actual_species = Column(String(160), nullable=True)
    predicted_species = Column(String(160), nullable=True)
    actual_conservation = Column(String(120), nullable=True)
    predicted_conservation = Column(String(120), nullable=True)
    actual_dbh_cm = Column(Float, nullable=True)
    predicted_dbh_cm = Column(Float, nullable=True)
    scan_success = Column(Boolean, nullable=False, default=False)
    app_success = Column(Boolean, nullable=False, default=False)
    latency_ms = Column(Float, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
