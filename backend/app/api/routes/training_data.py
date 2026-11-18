from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session
from app.core.security import require_admin
from app.db.database import get_db
from app.models.user import User
from app.schemas.training_data import TrainingDataList, TrainingExportRequest
from app.services.training_data import reviewed_examples, manifest_csv, export_archive

router = APIRouter()

@router.get('', response_model=TrainingDataList)
def list_training_data(q: str = Query('', max_length=200), offset: int = Query(0, ge=0),
                       limit: int = Query(50, ge=1, le=100), db: Session = Depends(get_db),
                       _: User = Depends(require_admin)):
    rows = reviewed_examples(db)
    if q.strip():
        query = q.strip().lower()
        rows = [row for row in rows if query in ' '.join(filter(None, [row.confirmed_common_name,
            row.confirmed_scientific_name, row.original_common_name, row.original_scientific_name])).lower()]
    return TrainingDataList(total=len(rows), ready=sum(row.ready for row in rows),
        corrected=sum(row.corrected for row in rows), items=rows[offset:offset + limit])

@router.get('/manifest.csv')
def export_manifest(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    rows = [row.model_dump(mode='json') for row in reviewed_examples(db) if row.ready]
    return Response(manifest_csv(rows), media_type='text/csv', headers={
        'Content-Disposition': 'attachment; filename="treetrace_reviewed_manifest.csv"',
        'Cache-Control': 'no-store',
    })

@router.post('/export')
def export_photos(payload: TrainingExportRequest, db: Session = Depends(get_db),
                  _: User = Depends(require_admin)):
    rows = {row.id: row for row in reviewed_examples(db)}
    selected = list(dict.fromkeys(payload.ids))
    if any(key not in rows or not rows[key].ready for key in selected):
        raise HTTPException(422, 'Only complete, independently confirmed examples can be exported. Refresh the list.')
    archive, count, failed = export_archive([rows[key] for key in selected])
    return Response(archive, media_type='application/zip', headers={
        'Content-Disposition': 'attachment; filename="treetrace_reviewed_photos.zip"',
        'X-Exported-Images': str(count), 'X-Export-Failures': str(failed), 'Cache-Control': 'no-store',
    })
