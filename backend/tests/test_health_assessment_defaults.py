from datetime import date
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.models.tree import Tree, HealthStatus
from app.models.tree_submission import TreeSubmission
from app.schemas.tree import TreeCreate, TreeUpdate, TreeOut
from app.schemas.tree_submission import TreeSubmissionCreate
from app.schemas.health_log import HealthLogCreate
from app.services.ai_identify import _build_wiki
from app.api.routes.health_logs import create_health_log
from app.api.routes.tree_submissions import approve_submission
from app.schemas.tree_submission import TreeSubmissionOverrides
from fastapi import Response
from app.models.user import User, UserRole
from app.models.unknown_species import UnknownSpecies  # Register submission FK target.
from app.db.health_schema import verify_health_status_schema


def test_unassessed_defaults_do_not_claim_healthy():
    assert TreeCreate(common_name='Mango').health_status == 'Not assessed'
    assert TreeSubmissionCreate().health_status == 'Not assessed'
    assert Tree.__table__.c.health_status.default.arg == HealthStatus.NotAssessed
    assert TreeSubmission.__table__.c.health_status.default.arg == 'Not assessed'


@pytest.mark.parametrize('status', ['Healthy', 'Fair', 'Poor', 'Not assessed'])
def test_status_contracts_accept_only_supported_assessments(status):
    assert TreeCreate(common_name='Mango', health_status=status).health_status == status
    assert TreeUpdate(health_status=status).health_status == status
    assert TreeSubmissionCreate(health_status=status).health_status == status
    assert HealthLogCreate(tree_id=1, condition=status, assessed_date=date.today()).condition == status


@pytest.mark.parametrize('status', ['Diseased', '', 'No symptoms', 'Unknown'])
def test_arbitrary_diagnoses_are_not_health_statuses(status):
    with pytest.raises(ValidationError):
        TreeCreate(common_name='Mango', health_status=status)
    with pytest.raises(ValidationError):
        HealthLogCreate(tree_id=1, condition=status, assessed_date=date.today())


def test_tree_update_cannot_replace_assessment_with_null():
    with pytest.raises(ValidationError):
        TreeUpdate(health_status=None)


def test_species_wiki_never_invents_photo_diagnoses():
    for common, scientific in [('Mango', 'Mangifera indica'), ('Unknown tree', '')]:
        assert _build_wiki(common, scientific, None, None, None)['common_problems'] == []


def test_citizen_still_cannot_confirm_official_health():
    payload = HealthLogCreate(tree_id=1, condition='Healthy', assessed_date=date.today())
    with pytest.raises(HTTPException) as exc:
        create_health_log(payload, db=None, current_user=SimpleNamespace(role='citizen'))
    assert exc.value.status_code == 403


def test_persisted_defaults_and_field_review_preserve_existing_tree(db_session):
    assessor = User(full_name='Reviewer', email='health@example.test',
                    hashed_password='unused', role=UserRole.field_worker)
    existing = Tree(common_name='Existing', health_status=HealthStatus.Healthy)
    new_tree = Tree(common_name='New tree')
    db_session.add_all([assessor, existing, new_tree])
    db_session.commit()
    db_session.refresh(new_tree)
    assert new_tree.health_status == HealthStatus.NotAssessed
    assert TreeOut.model_validate(new_tree).model_dump(mode='json')['health_status'] == 'Not assessed'
    result = create_health_log(
        HealthLogCreate(tree_id=new_tree.id, condition='Fair', assessed_date=date.today()),
        db=db_session, current_user=assessor)
    assert result['assessed_by_id'] == assessor.id
    db_session.refresh(new_tree)
    db_session.refresh(existing)
    assert new_tree.health_status == HealthStatus.Fair
    assert existing.health_status == HealthStatus.Healthy


@pytest.mark.parametrize('label_present', [True, False])
def test_postgres_preflight_blocks_missing_enum_label(label_present):
    from unittest.mock import MagicMock
    engine = MagicMock()
    engine.dialect.name = 'postgresql'
    engine.connect.return_value.__enter__.return_value.execute.return_value.mappings.return_value.all.return_value = [{
        'data_type': 'USER-DEFINED', 'accepts_not_assessed': label_present,
        'character_maximum_length': None}]
    if label_present:
        verify_health_status_schema(engine)
    else:
        with pytest.raises(RuntimeError, match='0004_add_not_assessed_health.sql'):
            verify_health_status_schema(engine)


def test_submission_approval_does_not_invent_healthy_status(db_session):
    reviewer = User(full_name='Reviewer', email='reviewer@example.test',
                    hashed_password='unused', role=UserRole.field_worker)
    submitter = User(full_name='Submitter', email='submitter@example.test',
                     hashed_password='unused', role=UserRole.citizen)
    db_session.add_all([reviewer, submitter])
    db_session.flush()
    submission = TreeSubmission(common_name='Mango', submitted_by_id=submitter.id,
                                health_status='Not assessed')
    db_session.add(submission)
    db_session.commit()
    result = approve_submission(submission.id, TreeSubmissionOverrides(), Response(),
                                db=db_session, current_user=reviewer)
    assert result['tree'].health_status == HealthStatus.NotAssessed
