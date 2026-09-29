# TreeTrace Development Context

`knowledge.md` is the system reference. `AGENTS.md` contains the rules for making changes safely.

## Quick Start

| Component | Directory | Setup | Run or check |
| --- | --- | --- |
| Backend | `backend/` | `pip install -r requirements.txt` | `uvicorn app.main:app --reload` |
| Web | `frontend/` | `npm install` | `npm run dev`, `npm run lint`, `npm run build` |
| Mobile | `mobile/` | `flutter pub get` | `flutter run`, `flutter analyze`, `flutter test` |

The backend normally runs at `http://localhost:8000`. The web application normally runs at `http://localhost:5173` and proxies `/api` to the backend. Flutter's API URL is configured separately in `mobile/lib/services/api_service.dart`; use the correct development or deployed URL for the target device.

## File Guide

| Need | Primary location |
| --- | --- |
| Register a backend route | `backend/app/main.py` |
| Implement an endpoint | `backend/app/api/routes/` |
| Change stored fields | `backend/app/models/` and `backend/app/schemas/` |
| Update authentication | `backend/app/core/security.py` |
| Change AI, species, or email behavior | `backend/app/services/` |
| Add a web request | `frontend/src/api/` |
| Register a web page | `frontend/src/App.jsx` |
| Change the mobile API client | `mobile/lib/services/api_service.dart` |
| Change mobile models or screens | `mobile/lib/models/` and `mobile/lib/screens/` |

## High-Value Checks

- Match endpoint paths, verbs, and payloads between FastAPI, React, and Flutter.
- Check the backend authorization path for every new or changed mutating operation.
- Do not include secrets in code or documentation. Use local environment configuration and deployment settings.
- Confirm both online and review-before-sync behavior for mobile changes that save records.
- Treat AI output as assistive data. Maintain its existing confidence, status, and review handling rather than presenting an inference as a guaranteed identification.

## Current Compatibility Note

The backend defines tree updates as `PATCH /api/trees/{id}`. Flutter currently sends `PUT /trees/{id}` in `ApiService.updateTree`; verify or correct this contract before changing mobile tree editing.
