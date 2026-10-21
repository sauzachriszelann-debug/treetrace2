"""G4 pending review and approval API (/api/tree-submissions).

Design contract (approved):
  * Any authenticated role may create a submission; the daily quota applies to
    citizens only and is taken INSIDE the insert transaction so an idempotent
    replay or a failed insert never consumes quota (safeguard B).
  * Staff (admin + field_worker) may approve / reject / link / reopen, but
    never their own submission (decision 9 safeguard).
  * All state transitions use an atomic compare-and-set
    (UPDATE ... WHERE status = <expected>) inside one transaction; approved
    and linked are terminal, rejected may be reopened to pending only
    (decisions 6-8).
  * Approval creates the trees row in the SAME transaction as the status
    flip; reviewer overrides are validated with the tree schema and stored
    separately so submitted evidence stays write-once (safeguard E).
  * Linking records an existing tree id without merging or overwriting any
    tree data, and MANY submissions may link to the same tree (safeguard A).
"""

import json
from datetime import date, datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.routes.trees import _estimate_tree_carbon, _identity_fingerprint
from app.core.security import get_current_user
from app.db.database import get_db
from app.models.tree import Tree
from app.models.tree_submission import TreeSubmission
from app.models.user import User, UserRole
from app.schemas.tree import TreeCreate
from app.schemas.tree_submission import (
    SubmissionLink,
    SubmissionOut,
    SubmissionReject,
    TreeSubmissionCreate,
    TreeSubmissionOverrides,
)

router = APIRouter()

# Decision 10: separate daily tree-submission quota (do NOT share the
# unknown-species counter). Staff are unlimited (existing platform rule).
TREE_SUBMISSION_DAILY_LIMITS = {
    "free": 10,
    "pro": 50,
    "professional": 50,
    "enterprise": None,
}


def _is_staff(user: User) -> bool:
    """Staff check tolerant of enum vs plain-string roles (mirrors
    require_admin in app/core/security.py)."""
    role = user.role
    if role in (UserRole.admin, UserRole.field_worker):
        return True
    return str(role).split(".")[-1].lower() in ("admin", "field_worker")


def require_staff(current_user: User = Depends(get_current_user)) -> User:
    if not _is_staff(current_user):
        raise HTTPException(
            status_code=403,
            detail="Review actions are available to admins and field workers.",
        )
    return current_user


def _reject_self_review(user: User, submission: TreeSubmission) -> None:
    """Decision 9 safeguard: nobody reviews their own submission."""
    if (
        submission.submitted_by_id is not None
        and submission.submitted_by_id == user.id
    ):
        raise HTTPException(
            status_code=403,
            detail="You cannot review your own submission.",
        )


def _parse_json(value: Optional[str], fallback):
    if not value:
        return fallback
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return fallback


def submission_out(submission: TreeSubmission) -> dict:
    return {
        "id": submission.id,
        "client_uuid": submission.client_uuid,
        "status": submission.status,
        "review_status": submission.status,
        "source": submission.source,
        "common_name": submission.common_name,
        "scientific_name": submission.scientific_name,
        "dbh_cm": submission.dbh_cm,
        "height_m": submission.height_m,
        "health_status": submission.health_status,
        "barangay": submission.barangay,
        "city": submission.city,
        "province": submission.province,
        "lat": submission.lat,
        "lng": submission.lng,
        "photo_url": submission.photo_url,
        "date_recorded": submission.date_recorded,
        "notes": submission.notes,
        "ai_candidates": _parse_json(submission.ai_candidates, []),
        "review_overrides": _parse_json(submission.review_overrides, None),
        "reviewed_by_id": submission.reviewed_by_id,
        "reviewed_by_name": (
            submission.reviewed_by.full_name if submission.reviewed_by else None
        ),
        "review_reason": submission.review_reason,
        "reviewed_at": submission.reviewed_at,
        "approved_tree_id": submission.approved_tree_id,
        "source_unknown_species_id": submission.source_unknown_species_id,
        "submitted_by_id": submission.submitted_by_id,
        "submitted_by_name": (
            submission.submitted_by.full_name if submission.submitted_by else None
        ),
        "submitted_by_email": (
            submission.submitted_by.email if submission.submitted_by else None
        ),
        "created_at": submission.created_at,
        "updated_at": submission.updated_at,
    }


def _take_submission_quota(db: Session, user: User) -> None:
    """Reserve one citizen submission slot atomically (safeguard B).

    * No-op for staff - unlimited, matching AI and unknown-species limits.
    * Locks the user row (SELECT ... FOR UPDATE) so concurrent submissions
      cannot exceed the plan limit; SQLite serializes writes anyway.
    * Deliberately does NOT commit: the increment commits together with the
      submission insert, so a failed insert (IntegrityError -> replay) or a
      402 rolls the reservation back and nothing is consumed.
    * Replays never reach this function - the create path checks for an
      existing client_uuid first.
    """
    if _is_staff(user):
        return

    locked = (
        db.query(User).filter(User.id == user.id).with_for_update().first()
    )
    if locked is None:
        return

    today = date.today()
    if locked.ai_usage_date != today:
        locked.ai_usage_date = today
        locked.ai_identifications_today = 0
        locked.unknown_submissions_today = 0
        locked.tree_submissions_today = 0

    plan = (locked.subscription_plan or "free").lower().strip()
    daily_limit = TREE_SUBMISSION_DAILY_LIMITS.get(
        plan, TREE_SUBMISSION_DAILY_LIMITS["free"]
    )
    if daily_limit is None:
        return

    used_today = locked.tree_submissions_today or 0
    if used_today >= daily_limit:
        db.rollback()  # discard any lazy-reset writes; nothing consumed
        plan_label = (
            "Starter"
            if plan == "free"
            else "Professional"
            if plan in ("pro", "professional")
            else "Enterprise"
        )
        raise HTTPException(
            status_code=402,
            detail=(
                f"You've used all {daily_limit} tree submissions for today "
                f"on the {plan_label} plan. Upgrade for higher daily access."
            ),
        )
    locked.tree_submissions_today = used_today + 1


def _submission_or_404(db: Session, submission_id: int) -> TreeSubmission:
    submission = (
        db.query(TreeSubmission)
        .filter(TreeSubmission.id == submission_id)
        .first()
    )
    if submission is None:
        raise HTTPException(
            status_code=404, detail="Tree submission not found"
        )
    return submission


def _state_conflict(submission: TreeSubmission, expected: str) -> HTTPException:
    return HTTPException(
        status_code=409,
        detail={
            "message": (
                f"This submission is '{submission.status}', not '{expected}'. "
                "No changes were made."
            ),
            "status": submission.status,
            "approved_tree_id": submission.approved_tree_id,
        },
    )


# ---------------------------------------------------------------------------
# Create
# ---------------------------------------------------------------------------

@router.post("/", status_code=201)
def create_submission(
    payload: TreeSubmissionCreate,
    response: Response,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a pending tree submission (any authenticated role).

    Idempotent when the client supplies ``client_uuid`` (G2 pattern): a
    replay returns HTTP 200 with ``Idempotent-Replay: true`` and consumes no
    quota; a key reused for a different identity is a 409, never a merge.
    """
    data = payload.model_dump()
    client_uuid = data.pop("client_uuid", None)
    client_uuid = str(client_uuid) if client_uuid is not None else None
    ai_candidates = data.pop("ai_candidates", None)
    source = data.pop("source", None)
    submitted = payload.model_dump(exclude={"client_uuid", "ai_candidates", "source"})

    def replay(existing: TreeSubmission):
        response.status_code = 200
        response.headers["Idempotent-Replay"] = "true"
        return submission_out(existing)

    if client_uuid is not None:
        existing = (
            db.query(TreeSubmission)
            .filter(TreeSubmission.client_uuid == client_uuid)
            .first()
        )
        if existing is not None:
            if (
                _identity_fingerprint(
                    payload.common_name,
                    payload.scientific_name,
                    payload.lat,
                    payload.lng,
                    payload.barangay,
                )
                != _identity_fingerprint(
                    existing.common_name,
                    existing.scientific_name,
                    existing.lat,
                    existing.lng,
                    existing.barangay,
                )
            ):
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            "This submission key is already associated with a "
                            "different submission. Nothing was merged or "
                            "overwritten."
                        ),
                        "existing_submission_id": existing.id,
                    },
                )
            return replay(existing)

    # Quota is reserved inside the insert transaction (safeguard B): a failed
    # insert below rolls it back, and replays returned above never consume.
    _take_submission_quota(db, current_user)

    for attempt in range(2):
        try:
            submission = TreeSubmission(
                **data,
                client_uuid=client_uuid,
                ai_candidates=(
                    json.dumps(ai_candidates) if ai_candidates is not None else None
                ),
                source=source,
                status="pending",
                submitted_by_id=current_user.id,
            )
            db.add(submission)
            db.commit()
            db.refresh(submission)
            return submission_out(submission)
        except IntegrityError as exc:
            db.rollback()
            # Recover ONLY from the client_uuid uniqueness violation; every
            # other integrity failure re-raises untouched (G2 discipline).
            message = str(exc)
            if client_uuid is None or "client_uuid" not in message:
                raise
            existing = (
                db.query(TreeSubmission)
                .filter(TreeSubmission.client_uuid == client_uuid)
                .first()
            )
            if existing is None:
                if attempt == 0:
                    continue
                raise HTTPException(
                    status_code=503,
                    detail=(
                        "Could not uniquely record this submission. "
                        "Please retry with the same submission key."
                    ),
                )
            if (
                _identity_fingerprint(
                    payload.common_name,
                    payload.scientific_name,
                    payload.lat,
                    payload.lng,
                    payload.barangay,
                )
                != _identity_fingerprint(
                    existing.common_name,
                    existing.scientific_name,
                    existing.lat,
                    existing.lng,
                    existing.barangay,
                )
            ):
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            "This submission key is already associated with a "
                            "different submission. Nothing was merged or "
                            "overwritten."
                        ),
                        "existing_submission_id": existing.id,
                    },
                )
            return replay(existing)


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

@router.get("/")
def list_submissions(
    status_filter: Optional[str] = Query(None, alias="status"),
    db: Session = Depends(get_db),
    _: User = Depends(require_staff),
):
    """Review queue (staff only), newest first, optional status filter."""
    q = db.query(TreeSubmission)
    if status_filter:
        q = q.filter(TreeSubmission.status == status_filter)
    entries = q.order_by(TreeSubmission.created_at.desc()).all()
    return [submission_out(entry) for entry in entries]


@router.get("/my")
def list_my_submissions(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The caller's own submissions with decisions (citizen visibility)."""
    entries = (
        db.query(TreeSubmission)
        .filter(TreeSubmission.submitted_by_id == current_user.id)
        .order_by(TreeSubmission.created_at.desc())
        .all()
    )
    return [submission_out(entry) for entry in entries]


# ---------------------------------------------------------------------------
# Review actions (staff; never self-review)
# ---------------------------------------------------------------------------

@router.post("/{submission_id}/approve")
def approve_submission(
    submission_id: int,
    payload: TreeSubmissionOverrides,
    response: Response,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Approve a pending submission into the official inventory.

    One transaction: create the trees row from (submitted + validated
    overrides), then flip status pending -> approved with a compare-and-set.
    A repeat or concurrent approve loses the CAS and gets 409 with the
    existing tree id - approval is a human decision, never a silent replay.
    """
    submission = _submission_or_404(db, submission_id)
    _reject_self_review(current_user, submission)
    if submission.status != "pending":
        raise _state_conflict(submission, "pending")

    overrides = payload.model_dump(exclude_unset=True)

    effective = {
        # Submitted evidence (write-once) as the base...
        "common_name": submission.common_name,
        "scientific_name": submission.scientific_name,
        "dbh_cm": submission.dbh_cm,
        "height_m": submission.height_m,
        "health_status": submission.health_status or "Healthy",
        "barangay": submission.barangay,
        "city": submission.city or "Panabo City",
        "province": submission.province or "Davao del Norte",
        "lat": submission.lat,
        "lng": submission.lng,
        "photo_url": submission.photo_url,
        "date_recorded": submission.date_recorded,
        "notes": submission.notes,
    }
    # ...then reviewer corrections, kept separately in review_overrides.
    effective.update(overrides)

    if not (effective.get("common_name") or "").strip():
        raise HTTPException(
            status_code=422,
            detail=(
                "A common_name is required before approval. Provide it as a "
                "review override or reopen the submission for the citizen."
            ),
        )

    # Safeguard E: the merged record must satisfy the existing tree schema.
    try:
        tree_payload = TreeCreate.model_validate(effective)
    except ValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": (
                    "Submitted data plus overrides do not form a valid tree "
                    "record."
                ),
                "errors": exc.errors(),
            },
        )

    biomass, carbon = _estimate_tree_carbon(
        tree_payload.dbh_cm, tree_payload.height_m
    )
    tree = Tree(
        **tree_payload.model_dump(exclude={"client_uuid"}),
        biomass_kg=biomass,
        carbon_kg=carbon,
        client_uuid=None,  # the G4 key belongs to the submission, not the tree
        recorded_by_id=current_user.id,
    )
    db.add(tree)
    db.flush()  # allocate tree.id inside the transaction

    # Atomic compare-and-set: exactly one approver can win this UPDATE.
    flipped = (
        db.query(TreeSubmission)
        .filter(
            TreeSubmission.id == submission_id,
            TreeSubmission.status == "pending",
        )
        .update(
            {
                TreeSubmission.status: "approved",
                TreeSubmission.reviewed_by_id: current_user.id,
                TreeSubmission.reviewed_at: datetime.now(timezone.utc),
                TreeSubmission.review_overrides: (
                    json.dumps(overrides) if overrides else None
                ),
                TreeSubmission.approved_tree_id: tree.id,
            },
            synchronize_session=False,
        )
    )
    if flipped != 1:
        db.rollback()  # removes the provisional tree too
        db.refresh(submission)
        raise _state_conflict(submission, "pending")

    db.commit()
    db.refresh(submission)
    db.refresh(tree)
    response.headers["X-Approved-Tree-Id"] = str(tree.id)
    return {"submission": submission_out(submission), "tree": tree}


@router.post("/{submission_id}/reject")
def reject_submission(
    submission_id: int,
    payload: SubmissionReject,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Reject a pending submission. A reason is mandatory (approved design)."""
    submission = _submission_or_404(db, submission_id)
    _reject_self_review(current_user, submission)
    reason = (payload.reason or "").strip()
    if not reason:
        raise HTTPException(
            status_code=422,
            detail="A rejection reason is required.",
        )
    flipped = (
        db.query(TreeSubmission)
        .filter(
            TreeSubmission.id == submission_id,
            TreeSubmission.status == "pending",
        )
        .update(
            {
                TreeSubmission.status: "rejected",
                TreeSubmission.reviewed_by_id: current_user.id,
                TreeSubmission.reviewed_at: datetime.now(timezone.utc),
                TreeSubmission.review_reason: reason,
            },
            synchronize_session=False,
        )
    )
    if flipped != 1:
        db.rollback()
        db.refresh(submission)
        raise _state_conflict(submission, "pending")
    db.commit()
    db.refresh(submission)
    return submission_out(submission)


@router.post("/{submission_id}/link")
def link_submission(
    submission_id: int,
    payload: SubmissionLink,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Link a pending submission to an EXISTING tree (decision 5).

    Creates no tree and merges/overwrites no data - advisory G3 discipline.
    Many submissions may link to the same tree (safeguard A): the partial
    unique index covers only approved rows.
    """
    submission = _submission_or_404(db, submission_id)
    _reject_self_review(current_user, submission)
    tree = db.query(Tree).filter(Tree.id == payload.tree_id).first()
    if tree is None:
        raise HTTPException(status_code=404, detail="Tree not found")
    flipped = (
        db.query(TreeSubmission)
        .filter(
            TreeSubmission.id == submission_id,
            TreeSubmission.status == "pending",
        )
        .update(
            {
                TreeSubmission.status: "linked",
                TreeSubmission.reviewed_by_id: current_user.id,
                TreeSubmission.reviewed_at: datetime.now(timezone.utc),
                TreeSubmission.approved_tree_id: tree.id,
            },
            synchronize_session=False,
        )
    )
    if flipped != 1:
        db.rollback()
        db.refresh(submission)
        raise _state_conflict(submission, "pending")
    db.commit()
    db.refresh(submission)
    return submission_out(submission)


@router.post("/{submission_id}/reopen")
def reopen_submission(
    submission_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Reopen a REJECTED submission back to pending (decision 6).

    The previous rejection reason is retained as history; the reviewer and
    timestamp are cleared. Approved and linked remain terminal.
    """
    submission = _submission_or_404(db, submission_id)
    _reject_self_review(current_user, submission)
    flipped = (
        db.query(TreeSubmission)
        .filter(
            TreeSubmission.id == submission_id,
            TreeSubmission.status == "rejected",
        )
        .update(
            {
                TreeSubmission.status: "pending",
                TreeSubmission.reviewed_by_id: None,
                TreeSubmission.reviewed_at: None,
            },
            synchronize_session=False,
        )
    )
    if flipped != 1:
        db.rollback()
        db.refresh(submission)
        raise _state_conflict(submission, "rejected")
    db.commit()
    db.refresh(submission)
    return submission_out(submission)
