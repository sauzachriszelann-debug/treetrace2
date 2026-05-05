# 🌿 TreeTrace — Panabo City Geo-Spatial Tree Inventory

A full-stack system for managing and exploring urban forest inventory.

## Project Structure

```
treetrace-web-flutter/
├── backend/          ← FastAPI (Python 3.11+)
├── frontend/         ← React 18 + Vite + Tailwind (Web)
└── mobile/           ← Flutter (Android + iOS + Web)
```

## Tech Stack

| Layer     | Technology                              |
|-----------|-----------------------------------------|
| Backend   | FastAPI (Python 3.11+)                  |
| Database  | MySQL 8 via SQLAlchemy ORM              |
| Auth      | JWT (python-jose + passlib/bcrypt)      |
| Storage   | Supabase (photos + QR only)             |
| Frontend  | React 18 + Vite + Tailwind CSS          |
| Mobile    | Flutter (consumes same REST API)        |
| AI        | Gemini API + Pl@ntNet + Claude Vision   |
| Email     | Gmail SMTP via smtplib                  |

---

## 🚀 Running the Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Backend runs at: `http://localhost:8000`

---

## 🌐 Running the Web Frontend

```bash
cd frontend
npm install
npm run dev
```

Web runs at: `http://localhost:5173`

---

## 📱 Running the Flutter Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

> For Android emulator: API URL is already set to `http://10.0.2.2:8000/api`
> For real device on same WiFi: change `kBaseUrl` in `lib/services/api_service.dart` to your PC's IP, e.g. `http://192.168.1.x:8000/api`

---

## 👥 User Roles

| Role         | Access                                          |
|--------------|-------------------------------------------------|
| Admin        | Full system — users, trees, reports, QR gen     |
| Field Worker | Add trees, health logs, AI identification       |
| Citizen      | Public portal, map, QR scan, 3 AI scans/day     |

---

## 🔧 Environment Setup

Copy `backend/.env.example` to `backend/.env` and fill in:

```env
SECRET_KEY=your-secret-key
DATABASE_URL=mysql+pymysql://root:@localhost:3306/treetracecp
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-key
GMAIL_USER=your@gmail.com
GMAIL_APP_PASSWORD=your-app-password
GEMINI_API_KEY=your-gemini-key
PLANTNET_API_KEY=your-plantnet-key
ANTHROPIC_API_KEY=your-anthropic-key
FRONTEND_URL=http://localhost:5173
```

---

## 📲 Features

### Web (React)
- 🗺️ Interactive tree map (OpenStreetMap)
- 🤖 AI species identification (Pl@ntNet + Claude)
- 📊 Community structure & biodiversity analytics
- 📱 QR code generation for each tree
- 🌿 Public tree encyclopedia (PictureThis-style)
- 👥 User management with email invites
- 📋 Health log tracking

### Mobile (Flutter)
- 📱 Native Android & iOS app
- 📷 Camera-based AI tree identification
- 🔍 QR code scanner
- 🗺️ Interactive map with tree markers
- 🌿 Public portal for citizen users
- 🔐 Role-based access (Admin / Field Worker / Citizen)

---

Made with 💚 for Panabo City
