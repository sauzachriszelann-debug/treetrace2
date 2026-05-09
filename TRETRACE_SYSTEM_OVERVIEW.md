# TreeTrace System Overview

## 1. What TreeTrace Is

TreeTrace is a geo-spatial tree inventory and conservation system for Panabo City. It helps citizens, field workers, and administrators record, view, identify, monitor, and protect trees using maps, QR codes, AI-assisted identification, and mobile field tools.

The system is designed for real conservation use:

- Citizens can explore public tree information, scan QR tree tags, view the public tree map, and use limited AI identification.
- Field workers can add tree records, assess tree health, use AI-assisted measurements, scan QR codes, and collect data in the field.
- Administrators can manage tree records, users, health logs, subscription access, and community-submitted unknown species.

TreeTrace also supports a technopreneurship model through Free, Professional, and Enterprise access.

## 2. Main Goal

The main goal of TreeTrace is to provide a digital, map-based, and AI-assisted tree inventory system that supports:

- urban forest monitoring
- endangered tree protection
- faster tree identification
- QR-based public tree profiles
- field data collection
- community participation
- LGU, school, DENR, and barangay-level tree management

## 3. System Users

### Citizen / Public User

Citizens are public users who can access conservation features without managing official records.

Main features:

- View the public tree portal
- View the public tree map
- Open public tree profiles
- Scan QR codes attached to trees
- Use AI tree identification with limits
- Submit unknown species for expert review
- Request Pro access

Citizens should not be able to edit official tree records.

### Field Worker

Field workers are operational users who collect and update tree inventory data.

Main features:

- Add tree records
- Upload tree photos
- Record DBH, height, location, health status, and notes
- Use AI identification to assist data entry
- Scan QR tree tags
- Use map-based navigation
- Submit health assessments
- Work with offline/sync support for field collection

### Administrator

Administrators manage the official system.

Main features:

- View dashboard analytics
- Manage tree records
- Manage users
- Approve or update user subscription plans
- Review unknown species submissions
- Monitor health logs
- Access reporting and map tools
- Sign out from Profile

## 4. Core System Features

### Tree Inventory

TreeTrace stores official tree records with:

- common name
- scientific name
- DBH in centimeters
- height in meters
- health status
- barangay/city
- GPS location
- photo URL
- QR code
- notes
- recorded user
- creation date

### Public Tree Map

The public map shows tree locations in Panabo City. Users can view tree markers, open tree profiles, and explore the mapped urban forest.

In the Flutter app, the Explore page includes an interactive map preview. The full map page allows users to move, zoom, and inspect tree markers.

### QR Code Scanning

Each tree can have a QR code that links to its profile. When a user scans the QR code:

1. The camera opens.
2. The QR code is detected.
3. The app extracts the tree ID from the URL.
4. The backend loads the public tree data.
5. A tree profile preview appears.
6. The user can open the full tree profile.

The QR scanner uses the phone camera and now has a transparent scanning window instead of a white camera area.

### AI Tree Identification

The AI Scan feature allows users to upload or take a tree photo. The backend sends the image to an AI vision model, which returns:

- possible common name
- scientific name
- confidence level
- conservation status
- estimated DBH
- estimated height
- description
- family
- habitat
- distinguishing features
- care information

The result is shown in an encyclopedia-style screen so users can learn about the tree after scanning.

Important note: AI DBH and height estimates are approximate. For accurate DBH, field workers should still measure circumference manually and calculate:

```text
DBH = circumference / pi
```

### Cannot Cut Warning

If AI or tree data identifies a protected, endangered, or regulated tree, the system shows a warning. This supports conservation and helps prevent accidental cutting of important species.

Purpose:

- show conservation value during capstone defense
- support environmental compliance
- inform citizens and field workers immediately
- strengthen the system's DENR/LGU relevance

### Unknown Species Submission

When AI cannot confidently identify a tree, citizens and field workers can submit the photo as an unknown species.

Flow:

1. User uploads or scans a tree photo.
2. AI fails or gives low confidence.
3. User submits the photo for expert review.
4. Admin reviews the submission.
5. The species can be added or corrected in the database.

This supports a retraining/community-learning module. Over time, TreeTrace can improve with more Philippine-specific tree data.

### Offline and Sync

Offline support is important for field workers in remote barangays where internet signal may be weak.

Offline flow:

1. Field worker records a tree or unknown species while offline.
2. The action is saved locally in the mobile app.
3. When internet returns, the app syncs queued actions to the backend.
4. Uploaded photos and records are submitted automatically.

This makes the app more deployable for real field work.

## 5. Monetization and Technopreneurship Model

TreeTrace uses a freemium and institutional subscription model.

### Starter / Free

Target users:

- citizens
- students
- casual public users

Possible features:

- view public tree map
- scan QR tree profiles
- view basic tree information
- limited AI identification
- submit unknown species

### Professional / Pro

Target users:

- researchers
- arborists
- active citizen scientists
- small organizations

Possible features:

- unlimited or higher AI identification limit
- advanced tree profiles
- more tree records
- priority unknown-species review
- dashboard and analytics access

Suggested price:

```text
PHP 99 / month
```

### Enterprise / Institutional

Target users:

- LGUs
- schools
- barangays
- DENR offices
- environmental organizations

Possible features:

- unlimited inventory access
- field worker accounts
- reporting tools
- analytics packages
- onboarding and training
- city-wide deployment support

Suggested price:

```text
PHP 399+ / month
```

The strongest profit opportunity is institutional use, not only individual users. LGUs, schools, and environmental offices are more realistic paying customers because they need data, reporting, and monitoring.

## 6. Main User Flows

### Citizen Flow

```text
Open app
-> Login/Register
-> Explore public portal
-> View public map or scan QR
-> Open tree profile
-> Use limited AI Scan
-> Submit unknown species if needed
-> Request Pro if advanced access is needed
```

### Field Worker Flow

```text
Login
-> Dashboard
-> Add Tree
-> Upload/take photo
-> AI assists identification
-> Enter DBH, height, health, location
-> Save record
-> Scan QR or update health logs
-> Sync later if offline
```

### Admin Flow

```text
Login
-> Dashboard
-> Manage trees/users
-> Review health logs
-> Update subscription plans
-> Review unknown species
-> Monitor map and reports
```

### AI Scan Flow

```text
User opens AI Scan
-> Takes photo or selects from gallery
-> Mobile app sends image to backend
-> Backend sends image to AI model
-> AI returns structured tree information
-> App displays encyclopedia-style result
-> User can submit unknown species or add to inventory depending on role
```

### Pro Upgrade Flow

```text
Citizen opens Upgrade Pro
-> Views Starter, Professional, and Enterprise plans
-> Requests Pro upgrade
-> Backend marks upgrade_requested = true
-> Admin sees request in dashboard
-> Admin approves by setting subscription_plan = pro
-> User receives Pro access
```

For future payment integration, GCash, Maya, PayMongo, or Stripe can be connected so Pro upgrade becomes automatic after payment verification.

## 7. System Architecture

TreeTrace has three main parts:

```text
Frontend Web App
Flutter Mobile App
FastAPI Backend
```

The backend connects to the hosted database and serves both the web app and mobile app.

### Web Frontend

Location:

```text
frontend/
```

Technology:

- React
- Vite
- Axios

Main pages:

- Dashboard
- Tree List
- Add Tree
- Tree Detail
- Tree Map
- Health Logs
- QR Manager
- AI Identify
- Public Portal
- Public Tree Profile
- Upgrade
- Admin Users

### Flutter Mobile App

Location:

```text
mobile/
```

Technology:

- Flutter
- Dio
- Provider
- Mobile Scanner
- Flutter Map
- Image Picker
- Secure Storage

Main screens:

- Splash
- Login
- Register
- Public Portal
- Public Tree Profile
- Dashboard
- Tree List
- Add Tree
- Map
- Scan QR
- AI Identify
- DBH Measure
- Upgrade
- Profile

### Backend API

Location:

```text
backend/
```

Technology:

- FastAPI
- SQLAlchemy
- PostgreSQL/Aiven
- Render deployment

Main route groups:

- `/api/auth`
- `/api/users`
- `/api/trees`
- `/api/health-logs`
- `/api/storage`
- `/api/public`
- `/api/ai`

## 8. Database

The system uses PostgreSQL hosted on Aiven.

Important tables/models:

- users
- trees
- health_logs
- unknown_species

Important user subscription fields:

- `subscription_plan`
- `upgrade_requested`
- `ai_identifications_today`
- `ai_usage_date`

These support the Free vs Pro feature limits.

## 9. Deployment

### Backend

The backend is deployed on Render.

Live API base URL:

```text
https://treetrace-1o7l.onrender.com/api
```

Render may sleep when inactive. Opening the backend root or health endpoint can wake it:

```text
https://treetrace-1o7l.onrender.com/
https://treetrace-1o7l.onrender.com/api/health
```

To redeploy after local backend changes:

```powershell
git add .
git commit -m "Update TreeTrace backend and mobile features"
git push
```

Then open Render Dashboard and confirm the backend service redeploys successfully.

### Web Frontend

For local development:

```powershell
cd frontend
npm run dev
```

Local web URL:

```text
http://localhost:5173
```

### Backend Local Development

For local backend testing:

```powershell
cd backend
uvicorn app.main:app --reload
```

Local backend URL:

```text
http://localhost:8000
```

### Flutter Mobile

For Flutter testing:

```powershell
cd mobile
flutter run
```

If testing on a real phone, the app uses the Render backend URL by default.

## 10. Important Notes for Defense

### Conservation Value

TreeTrace is not only a CRUD system. It supports conservation by warning users when a tree may be endangered or protected.

### Field Usefulness

Offline and sync support makes the system usable in barangays or field locations with poor signal.

### Technopreneurship Value

The system has a realistic revenue model:

- Free citizen access
- Professional subscription
- Enterprise/LGU subscription
- Training and onboarding
- Data analytics and reporting packages

### Scalability

TreeTrace can grow over time because citizens and field workers can submit unknown species, and admins can review and improve the database.

## 11. Current Known Limitations

- AI DBH and height estimates are approximate and should not replace manual measurement.
- Payment integration is currently represented by a Pro request flow; automatic payment verification can be added later.
- Live Render backend must be redeployed after backend route changes.
- Mobile camera features must be tested on real devices because browser/emulator behavior can differ.

## 12. Implemented Improvements and Remaining Future Work

Implemented:

- Admin review page for unknown species submissions
- Exportable CSV inventory report
- QR printing layout for tree tags
- Expanded DENR/IUCN-style conservation reference list
- Role-specific analytics for admin users
- Field worker route planning endpoint and web tool
- More accurate DBH workflow using manual circumference or reference-object photo measurement

Remaining future work:

- Add PayMongo, GCash, Maya, or Stripe payment verification
- Add PDF report formatting
- Add payment receipt tracking and automatic Pro activation
