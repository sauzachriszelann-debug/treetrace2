---
name: treetrace-tree-inventory-workflow
description: Change TreeTrace tree inventory, health, geospatial, QR, carbon, or species-identification workflows while preserving data integrity and role permissions.
---

# TreeTrace Tree Inventory Workflow

Use this skill for changes involving tree records, health logs, geographic fields, measurements, carbon values, QR/public tree profiles, or AI-assisted species workflows. Do not use it for unrelated account, layout, or generic infrastructure work.

## Identify the Affected Domain

- Tree persistence and contracts: `backend/app/models/tree.py` and `backend/app/schemas/tree.py`
- Tree operations: `backend/app/api/routes/trees.py`
- Health assessment behavior: `backend/app/api/routes/health_logs.py`
- Public QR and profile behavior: `backend/app/api/routes/public.py`
- AI and species behavior: `backend/app/api/routes/identify.py` and `backend/app/services/`
- Client integrations: `frontend/src/api/trees.js`, `frontend/src/api/ai.js`, and `mobile/lib/services/api_service.dart`

Trace each relevant consumer before changing a shared field, calculation, route, or state.

## Protect Domain Invariants

- `common_name` is required for a tree record. Preserve its relationship to species lookup and conservation data.
- Preserve DBH units in centimeters and height units in meters. When DBH or height changes, retain the backend's biomass/carbon recalculation behavior unless an explicit user-supplied carbon value is intended to take precedence.
- A newly created health log updates the parent tree's current health status. Do not break that synchronization.
- Official tree and health changes are staff workflows; citizens cannot create, edit, or delete them. Tree deletion is admin-only and cascades to health logs.
- Coordinates, barangay, and media URLs may be optional, but do not invent location or media values when data is unavailable.
- Public endpoints and QR flows are readable without authentication. Keep user identities, staff notes, and secrets out of their responses.
- AI output is assistive. Preserve confidence, review, and unknown-species pathways rather than treating a prediction as guaranteed fact.

## Test the Workflow

For changes that mutate inventory data, exercise the create or update path, retrieve the result, and check role restrictions. Test the corresponding public or client-facing view when it is affected.

When editing a mobile workflow, preserve offline queue behavior: actions stay local until a user verifies them, and only verified actions are synchronized.

Run the relevant backend route checks plus `npm run lint` and `npm run build` for web changes, or `flutter analyze` and `flutter test` for mobile changes.
