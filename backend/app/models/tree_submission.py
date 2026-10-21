from sqlalchemy import (
    Column, Integer, String, Float, Date, Text,
    DateTime, ForeignKey, CheckConstraint, UniqueConstraint, Index, text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base

# Allowed record states. State machine (enforced in
# app/api/routes/tree_submissions.py with an atomic compare-and-set, and
# backstopped by the CHECK constraint below):
#   pending  -> approved | rejected | linked
#   rejected -> pending (reopen only)
#   approved, linked are terminal.
SUBMISSION_STATUSES = ("pending", "approved", "rejected", "linked")


class TreeSubmission(Base):
    """A citizen/staff-proposed tree record awaiting authorized review (G4).

    Structurally separate from ``trees``: pending rows are invisible to every
    inventory surface (list, map, stats, CSV, QR, nearby) because those
    queries only touch the ``trees`` table.
    """

    __tablename__ = "tree_submissions"

    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'approved', 'rejected', 'linked')",
            name="ck_tree_submissions_status",
        ),
        # G2 idempotency pattern, independent of trees.client_uuid.
        # NULLs are distinct in both PostgreSQL and SQLite, so submissions
        # without a key never collide.
        UniqueConstraint("client_uuid", name="ux_tree_submissions_client_uuid"),
        # One unknown-species entry can yield at most ONE tree submission
        # (conversion replay safety). NULLs are distinct, so Path-A
        # submissions (no source entry) are unaffected.
        UniqueConstraint(
            "source_unknown_species_id",
            name="ux_tree_submissions_source_unknown_species",
        ),
        # Safeguard A: uniqueness applies ONLY to approved submissions, which
        # each own exactly one NEW tree they created. Linked submissions
        # intentionally share approved_tree_id freely - many submissions may
        # reference the same existing tree - so the partial predicate keeps
        # them out of the index entirely.
        Index(
            "ux_tree_submissions_approved",
            "approved_tree_id",
            unique=True,
            sqlite_where=text("status = 'approved'"),
            postgresql_where=text("status = 'approved'"),
        ),
    )

    id = Column(Integer, primary_key=True, index=True)

    # G2-style idempotency key supplied by clients; NULL for conversions and
    # legacy callers. Uniqueness comes from the named constraint above.
    client_uuid = Column(String(36), nullable=True)

    # Record state; see SUBMISSION_STATUSES.
    status = Column(String(40), nullable=False, default="pending")

    # Origin: "web_form" | "mobile" | "ai_identify" (free-form enough for
    # future sources; not constrained at the DB level).
    source = Column(String(30), nullable=True)

    # Proposed tree payload - mirrors trees columns field-for-field. All
    # nullable here: evidence may be incomplete; the reviewer supplies what
    # is missing via approve-time overrides. common_name becomes mandatory
    # only at approval (the single required trees field).
    common_name = Column(String(150), nullable=True, index=True)
    scientific_name = Column(String(150), nullable=True)
    dbh_cm = Column(Float, nullable=True)
    height_m = Column(Float, nullable=True)
    health_status = Column(String(40), nullable=True, default="Healthy")
    barangay = Column(String(120), nullable=True)
    city = Column(String(120), nullable=True, default="Panabo City")
    province = Column(String(120), nullable=True, default="Davao del Norte")
    lat = Column(Float, nullable=True)
    lng = Column(Float, nullable=True)
    photo_url = Column(String(500), nullable=True)
    date_recorded = Column(Date, nullable=True)
    notes = Column(Text, nullable=True)

    # JSON list of AI candidates (Path A / conversion provenance).
    ai_candidates = Column(Text, nullable=True)

    # Reviewer corrections (JSON), stored SEPARATELY so the submitted
    # evidence above remains write-once and unchanged forever.
    review_overrides = Column(Text, nullable=True)

    # Review bookkeeping.
    reviewed_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    reviewed_by = relationship("User", foreign_keys=[reviewed_by_id])
    review_reason = Column(Text, nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)

    # Tree this submission resolved to: the NEW tree created on approval, or
    # the EXISTING tree recorded on link. No FK on purpose - trees may be
    # deleted by admins, and a dangling provenance pointer is preferred over
    # silently rewriting terminal states.
    approved_tree_id = Column(Integer, nullable=True)

    # Path B provenance: the unknown-species entry this submission was
    # converted from (unique). The entry itself is never modified.
    source_unknown_species_id = Column(
        Integer, ForeignKey("unknown_species.id"), nullable=True
    )
    source_unknown_species = relationship("UnknownSpecies")

    # Original submitter - preserved verbatim on conversion (may differ from
    # the reviewer who triggered the conversion).
    submitted_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    submitted_by = relationship("User", foreign_keys=[submitted_by_id])

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
