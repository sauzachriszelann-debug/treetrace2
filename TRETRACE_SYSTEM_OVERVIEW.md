# TreeTrace System Overview

## 1. System Description

TreeTrace is a geo-spatial tree inventory, monitoring, and conservation system designed for Panabo City. It helps citizens, field workers, and administrators identify trees, record tree data, view tree locations on a map, scan QR tree tags, monitor tree health, and protect endangered or regulated species.

The system is composed of:

- a web dashboard for administrators and staff
- a Flutter mobile app for citizens and field workers
- a FastAPI backend connected to a hosted PostgreSQL database
- AI-assisted tree identification and conservation warning features
- map-based public tree profiles and QR code access

TreeTrace is not only a record management system. It is designed as a conservation and technopreneurship platform that can support LGUs, schools, barangays, DENR-related offices, environmental groups, and citizen scientists.

## 2. Main Purpose

The main purpose of TreeTrace is to provide a digital and AI-assisted tree monitoring system that can:

- create a centralized tree inventory
- map trees using GPS coordinates
- identify trees using AI image analysis
- warn users when a tree may be endangered or protected
- allow citizens to access public tree information
- help field workers collect tree data in the field
- support offline field collection and later syncing
- allow unknown species submissions for expert review
- support reports, QR labels, and role-based analytics
- provide a realistic business model through Free, Professional, and Enterprise access

## 3. Target Users

### Citizen / Public User

Citizens can use TreeTrace for public conservation awareness and basic tree discovery. They should not manage official inventory records.

Citizen features:

- view the public portal
- view the public tree map
- open public tree profiles
- scan QR tree tags
- use limited AI tree identification based on plan
- submit unknown species for expert review based on plan
- view their AI identification activity
- view their unknown species submissions
- request Professional access

Citizen restriction:

- citizens cannot add, edit, or delete official inventory trees

### Field Worker

Field workers are operational users who collect and update tree inventory data.

Field worker features:

- add official tree records
- upload tree photos
- record DBH, height, health status, barangay, and GPS location
- use AI assistance for tree identification
- scan QR tree tags
- use the interactive map
- submit health logs
- save actions offline and sync later when internet is available

### Administrator

Administrators manage the official system, users, reviews, and reports.

Admin features:

- view dashboard analytics
- manage tree records
- manage users and roles
- review unknown species submissions
- update subscription plans
- view role-specific analytics
- access reports and QR printing tools
- monitor health logs
- sign out from the Profile screen

## 4. Core Features

### 4.1 Tree Inventory

TreeTrace stores official tree records with:

- common name
- scientific name
- DBH in centimeters
- height in meters
- estimated carbon value
- health status
- barangay and city
- GPS latitude and longitude
- photo URL
- QR code
- notes
- date recorded
- assigned or recorded user

This inventory becomes the official tree database used by the map, public profiles, reports, QR labels, and analytics.

### 4.2 Public Tree Map

The public tree map shows mapped trees in Panabo City. Users can move around the map, zoom, search, and open tree markers.

Current mobile map features:

- searchable tree map
- search by common name, scientific name, barangay, city, or health status
- map marker filtering by health status
- satellite/map toggle
- movable and zoomable map
- zoom cap to avoid unavailable tile levels
- tree marker preview popup

The Flutter Explore page also includes a map preview card. Citizens can open the full map from the Explore screen.

### 4.3 QR Code Scanning

Each tree can have a QR code that links to its public tree profile.

QR scan flow:

```text
User opens Scan QR
-> Camera scanner opens
-> User scans the tree tag
-> App reads the tree profile link or tree ID
-> Backend loads the public tree record
-> App shows a tree preview
-> User opens the full tree profile
```

The mobile QR scanner includes:

- visible "Scan Tree Tag" title
- back button
- transparent scanner window
- camera-based QR detection
- tree profile preview after scanning

### 4.4 AI Tree Identification

The AI Scan feature allows users to upload or capture a tree photo. The backend sends the image to an AI vision model and returns structured tree information.

AI result may include:

- possible common name
- scientific name
- confidence level
- conservation status
- estimated DBH
- estimated height
- family
- habitat
- description
- distinguishing features
- uses and ecological value
- care information

The Flutter app displays the result in an encyclopedia-style output so users can learn about the tree after scanning.

Important note:

AI DBH and height are only estimates. Accurate DBH should still be measured manually in the field using circumference:

```text
DBH = circumference / pi
```

### 4.5 Cannot Cut Warning

TreeTrace shows a warning when a tree is identified as endangered, protected, threatened, vulnerable, or regulated.

Purpose:

- prevent accidental cutting of important species
- support conservation awareness
- strengthen DENR/LGU relevance
- show real environmental value during capstone defense

This feature is important because it proves that TreeTrace is not only for storing data. It actively helps protect trees.

### 4.6 Unknown Species Submission

Unknown species submission allows citizens and field workers to send tree photos for expert review.

Flow:

```text
User scans or uploads a tree photo
-> AI result is unknown or low confidence
-> User submits the photo as an unknown species
-> Admin reviews the submission
-> Admin can approve, reject, or identify the species
-> The database can improve over time
```

This supports a community-learning and future retraining module. It is useful for Philippine-specific trees because local users can contribute real field data.

### 4.7 Offline and Sync

Offline support is useful for field workers in remote barangays with weak or unavailable signal.

Offline flow:

```text
Field worker records data while offline
-> App saves the action locally
-> User continues field work
-> Internet returns
-> App syncs queued actions to the backend
```

This makes TreeTrace more realistic for actual deployment because field work cannot always depend on stable internet.

### 4.8 Reports, QR Printing, and Tools

TreeTrace includes reporting and utility tools for administrative and institutional use.

Implemented tools:

- CSV inventory export
- printable inventory report that can be saved as PDF
- QR label printing layout
- role-based user analytics
- business/revenue metrics for Pro and institutional access
- unknown species review
- field worker route planning endpoint and web tool

These tools support LGU, school, barangay, and environmental office workflows.

## 5. Mobile App Flow

### Citizen Mobile Flow

```text
Open app
-> Login or register
-> Explore public portal
-> View tree map
-> Scan QR tree tag
-> Open public tree profile
-> Use limited AI Scan
-> Submit unknown species if needed
-> View personal AI and unknown species records in Profile
-> Request Professional access if needed
```

### Field Worker Mobile Flow

```text
Login
-> Dashboard
-> Add Tree
-> Upload or capture photo
-> Use AI assistance
-> Enter DBH, height, health, and location
-> Save official record
-> Scan QR or update health logs
-> Sync offline actions later if needed
```

### Admin Mobile Flow

```text
Login
-> Dashboard
-> View system data
-> Access profile
-> Sign out from Profile
```

The full administrative workflow is mainly handled in the web dashboard.

## 6. Web App Flow

### Admin Web Flow

```text
Login
-> Dashboard
-> Manage trees and users
-> Review unknown species
-> View health logs
-> Generate reports
-> Print QR labels
-> Update user access plans
```

### Public Web Flow

```text
Open public portal
-> View public map
-> Open public tree profile
-> Use AI identify if logged in
-> Request Pro access if advanced access is needed
```

## 7. Monetization and Technopreneurship Model

TreeTrace uses a freemium and institutional subscription model.

### Starter / Free

Target users:

- citizens
- students
- casual public users

Included access:

- public tree map
- public tree profiles
- unlimited QR scanning
- 10 AI identifications per day
- 15 unknown species submissions per day

### Professional / Pro

Target users:

- researchers
- active citizen scientists
- arborists
- small organizations

Possible access:

- 50 AI identifications per day
- 100 unknown species submissions per day
- more advanced tree information
- priority unknown species review
- dashboard and analytics access
- expanded records and monitoring tools

Suggested price:

```text
PHP 99 / month
```

### Enterprise / Institutional

Target users:

- LGUs
- schools
- barangays
- DENR-related offices
- environmental organizations

Possible access:

- unlimited AI identification
- unlimited unknown species submissions
- field worker accounts
- reporting tools
- analytics packages
- onboarding and training
- city-wide or campus-wide deployment support

Suggested price:

```text
PHP 399+ / month
```

### Additional Revenue Streams

TreeTrace can also earn from:

- training and onboarding services
- data analytics and reporting packages
- QR label setup and printing support
- institutional deployment packages
- maintenance and support services

The strongest profit opportunity is institutional use. LGUs, schools, barangays, and environmental offices are more realistic paying customers because they need organized inventory data, reports, monitoring, and compliance support.

## 8. Pro Upgrade Flow

Current implemented flow:

```text
Citizen opens Upgrade screen
-> User views Starter, Professional, and Enterprise plans
-> User requests Professional access
-> Backend marks upgrade_requested = true
-> Admin reviews the request
-> Admin updates the user's subscription plan
-> User receives Pro access
```

Payment verification is not yet connected. This is intentional for the current version. The current system demonstrates the monetization flow without requiring real payment processing.

Future payment flow:

```text
User chooses plan
-> User pays through PayMongo, GCash, Maya, or Stripe
-> Payment provider verifies payment
-> Backend records payment receipt
-> User subscription automatically changes to Pro
```

## 9. System Architecture

TreeTrace has three main components:

```text
React Web Frontend
Flutter Mobile App
FastAPI Backend
```

The backend connects to a hosted PostgreSQL database and serves both the web and mobile applications.

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
- Reports and Tools
- Unknown Species Review

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
- PostgreSQL
- Aiven database hosting
- Render backend deployment

Main route groups:

- `/api/auth`
- `/api/users`
- `/api/trees`
- `/api/health-logs`
- `/api/storage`
- `/api/public`
- `/api/ai`

## 10. Database

The system uses PostgreSQL hosted on Aiven.

Important tables/models:

- users
- trees
- health_logs
- unknown_species

Important user access fields:

- `role`
- `subscription_plan`
- `upgrade_requested`
- `ai_identifications_today`
- `unknown_submissions_today`
- `ai_usage_date`

These fields support role-based access, AI usage limits, and the Free vs Pro model.

## 11. Deployment

### Backend

The backend is deployed on Render.

Live API base URL:

```text
https://treetrace-1o7l.onrender.com/api
```

Render may sleep when inactive. To wake the backend, open:

```text
https://treetrace-1o7l.onrender.com/
https://treetrace-1o7l.onrender.com/api/health
```

If `/api` shows `{"detail":"Not Found"}`, that is normal because `/api` alone is not a route. Use the actual routes such as `/api/health`.

### Local Web Frontend

```powershell
cd frontend
npm run dev
```

Local URL:

```text
http://localhost:5173
```

### Local Backend

```powershell
cd backend
uvicorn app.main:app --reload
```

Local URL:

```text
http://localhost:8000
```

### Flutter Mobile

```powershell
cd mobile
flutter run
```

When installed on a real phone, the mobile app should use the deployed Render backend so the phone can connect from anywhere with internet access.

## 12. Important Defense Points

### Conservation Value

TreeTrace supports conservation through AI identification, endangered/protected tree warnings, public education, and QR-based access to tree profiles.

### Field Usefulness

The system supports field workers through mobile data collection, map access, QR scanning, DBH workflows, and offline/sync capability.

### Community Participation

Citizens can contribute through AI identification and unknown species submissions, helping the system collect more local tree data.

### Technopreneurship Value

TreeTrace has a realistic business model:

- free citizen access
- Professional subscriptions
- Enterprise/LGU packages
- training and onboarding services
- reporting and analytics packages
- QR tag deployment support

### Scalability

TreeTrace can expand from Panabo City to schools, barangays, campuses, parks, and other LGU areas.

## 13. Current Known Limitations

- AI DBH and height estimates are approximate.
- Manual circumference measurement is still the best DBH method.
- Payment verification is not yet connected.
- Automatic Pro activation after payment is not yet implemented.
- Mobile camera features should be tested on a real Android phone.
- Render backend may need a few seconds to wake up after inactivity.

## 14. Implemented Improvements

Already implemented:

- Cannot Cut warning for endangered/protected species
- Offline and sync support concept/workflow in mobile
- Unknown species submission
- Admin unknown species review page
- CSV inventory export
- Printable inventory report that can be saved as PDF
- QR printing layout for tree labels
- Role-specific analytics
- Business/revenue metrics for Pro and institutional plans
- Field worker route planning endpoint and web tool
- AI identification records for citizens
- Unknown species history for citizens
- Improved admin unknown species review with submitter details, AI candidates, identified, closed, and pending states
- Citizen restriction from adding official inventory trees
- Flutter public portal map card
- Flutter searchable and movable map
- Flutter QR scanner screen with visible title
- Flutter AI scanner screen with visible title
- Flutter center AI Scan button and quick action cards
- Profile-based logout

## 15. Remaining Future Improvements

These are good future improvements, but they are not required for the current working version unless the project scope expands.

### Payment Verification

Add PayMongo, GCash, Maya, or Stripe so users can pay directly inside the system. After payment, the backend should verify the transaction and automatically activate Pro access.

### Payment Receipt Tracking

Store payment receipts, transaction IDs, payment status, amount, plan type, and payment date. This helps admins audit subscription payments.

### Automatic Pro Activation

After a successful verified payment, the system can automatically change the user's plan from Free to Pro without admin approval.

### More DENR/IUCN References

Expand the conservation reference list using more official sources so the Cannot Cut warning becomes stronger and more defensible.

### Advanced Route Planning

Improve field worker route planning so staff can visit assigned trees in the most efficient order.

### More Accurate DBH Workflow

Improve DBH measurement using manual circumference input, reference-object photo measurement, or future AR/depth-assisted measurement.

## 16. Summary

TreeTrace is a conservation-focused, AI-assisted, map-based tree monitoring system. It supports public awareness, field data collection, QR tree profiles, unknown species review, endangered tree protection, and a realistic subscription-based business model.

For capstone defense, the strongest points are:

- real conservation impact through Cannot Cut warnings
- field usefulness through mobile and offline/sync workflows
- community participation through unknown species submissions
- technopreneurship through Free, Pro, and Enterprise access
- scalability for LGUs, schools, barangays, and environmental organizations
