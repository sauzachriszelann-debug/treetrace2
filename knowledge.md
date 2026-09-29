# TreeTrace Project Knowledge

## Project Overview

TreeTrace is a geo-spatial tree inventory system for Panabo City.

The system is designed to manage, explore, and monitor urban forest inventory. It supports administrators, field workers, and citizens through web and mobile applications.

## Project Structure

The repository contains three main parts:

- `backend/` - FastAPI backend using Python 3.11+
- `frontend/` - React web application using Vite and Tailwind CSS
- `mobile/` - Flutter application for Android, iOS, and Web

## Technology Stack

### Backend

- FastAPI
- Python 3.11+
- SQLAlchemy ORM
- JWT authentication
- python-jose
- passlib/bcrypt

### Database

- PostgreSQL
- Hosted on Aiven
- Accessed through SQLAlchemy ORM

### Storage

- Supabase for tree photos and QR-related storage

### Web Frontend

- React 18
- Vite
- Tailwind CSS

### Mobile

- Flutter
- Dart
- Android
- iOS
- Web

### AI

- Gemini API
- PlantNet
- Claude Vision

### Email

- Gmail SMTP using Python `smtplib`

## User Roles

### Admin

Administrators have full access to the system, including:

- User management
- Tree management
- Reports
- QR code generation

### Field Worker

Field workers can:

- Add trees
- Record tree health logs
- Perform AI tree identification

### Citizen

Citizens can:

- Access the public portal
- View the tree map
- Scan tree QR codes
- Perform up to 3 AI scans per day

## Web Features

The React web application includes:

- Interactive tree map using OpenStreetMap
- AI species identification using PlantNet and Claude
- Community structure and biodiversity analytics
- QR code generation for trees
- Public tree encyclopedia
- User management and email invitations
- Tree health log tracking

## Mobile Features

The Flutter application includes:

- Native Android and iOS support
- Camera-based AI tree identification
- QR code scanning
- Interactive map with tree markers
- Public citizen portal
- Role-based access control

## Implementation Notes

## Architecture

| Layer | Location | Responsibility |
| --- | --- | --- |
| API | `backend/` | FastAPI REST API, authorization, SQLAlchemy persistence, AI and storage integrations |
| Web app | `frontend/` | React/Vite administrative and public web experience |
| Mobile app | `mobile/` | Flutter application for field and public workflows, including offline queues |
| Research assets | `capstone/` | Thesis documents, diagrams, and evaluation material |

The backend is the source of truth. Both clients communicate with it under `/api`. The Vite development server proxies `/api` to `VITE_API_PROXY_TARGET` or `http://localhost:8000`; Flutter defines its API base URL in `mobile/lib/services/api_service.dart`.

## Backend Layout

- `app/main.py` creates the API, configures CORS, runs startup schema synchronization, and registers route groups.
- `app/api/routes/` owns endpoint behavior.
- `app/models/` owns SQLAlchemy database models and relationships.
- `app/schemas/` owns request and response contracts.
- `app/services/` contains AI identification, species data, local classification, and email logic.
- `app/core/` contains environment settings and JWT/password security.
- `app/db/database.py` configures the SQLAlchemy engine and request-scoped database sessions.

The database configuration uses SQLAlchemy with PostgreSQL. The production database is hosted on Aiven. The configuration accepts PostgreSQL-style URLs, including conversion from `postgres://` to `postgresql://`. Verify the active `DATABASE_URL` and deployment settings before making database-specific assumptions.

## User Roles and Access Model

| Role | Intended access |
| --- | --- |
| `admin` | Manages users, deletes trees, reviews unknown species, and has unrestricted staff AI access |
| `field_worker` | Adds and updates official tree records and health logs; has unrestricted staff AI access |
| `citizen` | Uses public features, submits unknown species and planting recommendations, but cannot create or change official inventory or health records |

Authorization is enforced in the FastAPI routes with JWT-backed `get_current_user` and `require_admin`. Client-side visibility is helpful but never sufficient for access control. Public registration always creates a citizen account, even if a caller sends another role.

## Core Data and Invariants

### Trees

`Tree` is the central record. A tree requires `common_name` and can include scientific name, DBH in centimeters, height in meters, biomass/carbon values, health status, barangay/city/province, coordinates, media URLs, date recorded, notes, and the recording user.

- Health status is `Healthy`, `Fair`, or `Poor`.
- When a tree is created without a carbon value, or its DBH/height is changed without an explicit carbon value, the backend estimates biomass and carbon.
- Conservation status, protection, and cutting permission are derived from the local species database rather than stored as editable tree fields.
- Deleting a tree is admin-only. Its health-log relationship cascades, so deletion is a consequential operation.

### Health Logs

Health logs are linked to a tree and assessor. Creating a health log also updates the parent tree's current health status. Citizens cannot create or delete official health logs.

### Unknown Species and AI Usage

AI identification accepts image uploads and can combine local classification with external species services. Unknown-species submissions are stored for admin review. Citizen use is counted per day by subscription plan; staff users are unlimited.

### Planting Recommendations

Staff can create recommendations directly. Citizen-created recommendations begin as `pending`, cannot set review status or planted state, and may only be edited by the submitting user while still pending.

## API Route Map

| Prefix | Main responsibility |
| --- | --- |
| `/api/auth` | Register, login, current-user profile |
| `/api/users` | Admin user management, role/subscription changes, account activation, upgrade requests, role analytics |
| `/api/trees` | Protected inventory CRUD, summary statistics, CSV export, QR labels, and route planning |
| `/api/health-logs` | Protected health-log history and updates |
| `/api/storage` | Authenticated Supabase photo and QR uploads/deletions |
| `/api/public` | Unauthenticated tree profiles, public tree listings, health history, and tree wiki content |
| `/api/ai` | AI usage, identification, DBH estimation, species lookup, biodiversity statistics, and unknown-species review |
| `/api/evaluation` | Evaluation rows, CSV import, aggregate results, and reset operations |
| `/api/planting` | Planting recommendations and inventory-informed suggestions |

## Client Integration Notes

- React API modules live in `frontend/src/api/`; routes are composed in `frontend/src/App.jsx`.
- Flutter API methods live in `mobile/lib/services/api_service.dart`; models are in `mobile/lib/models/models.dart`.
- Mobile offline actions remain queued until marked verified, then `syncOfflineQueue` sends them when connectivity returns.
- The backend tree-update contract is `PATCH /api/trees/{id}`. The Flutter `updateTree` method currently uses `PUT`, so mobile tree updates require compatibility verification before relying on them.
- Web DBH estimation uses multipart `POST /api/ai/measure-dbh-file`; Flutter uses JSON/base64 `POST /api/ai/measure-dbh`. Both endpoints are implemented.

## Integrations and Configuration

- SQLAlchemy database connection: `DATABASE_URL`
- JWT: `SECRET_KEY`, `ALGORITHM`, and token expiry configuration
- Supabase media storage: URL, service-role key, photo bucket, QR bucket
- AI and botanical enrichment: Pl@ntNet, Gemini, Anthropic, Perenual, Trefle, GBIF, plus optional local model assets
- Transactional email: Resend configuration

Credentials belong in local `backend/.env` or deployment configuration only. Do not commit keys, passwords, service-role values, or production URLs. Model files and service availability should be checked before enabling or changing AI-dependent workflows.

## Verification Commands

| Area | Commands |
| --- | --- |
| Backend | `pip install -r requirements.txt`, then `uvicorn app.main:app --reload` from `backend/` |
| Web | `npm run lint` and `npm run build` from `frontend/` |
| Mobile | `flutter analyze` and `flutter test` from `mobile/` |

Run the checks relevant to the changed layer. A shared API change needs contract checks in every affected client.
