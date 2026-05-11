# TreeTrace Technopreneurship and System Flow

## 1. System Overview

TreeTrace is an AI-assisted tree inventory, monitoring, and public awareness system for Panabo City and similar local government or institutional deployments.

The system combines:

- Public tree map
- QR-based tree profiles
- AI tree identification
- Cannot Cut endangered species warning
- Unknown species submission and expert review
- Field worker inventory tools
- Admin dashboard, reports, QR labels, users, and analytics
- Subscription-based Pro access for public users and institutional access for LGUs, schools, and organizations

The goal is both conservation and sustainability as a business. Public users can access basic conservation tools for free, while advanced usage and institutional management features create possible revenue.

## 2. Main Users

### Citizen / Public User

Citizens are general public users who can:

- View public tree map
- Open public tree profiles
- Scan QR tags
- Use limited AI identification
- Submit unknown species for expert review
- Request Pro access if they need higher limits

Citizens do not directly add or edit official inventory trees.

### Field Worker

Field workers are official staff or assigned personnel. They can:

- Add official tree records
- Update tree information
- View tree map
- Use AI scan
- Scan QR tags
- View dashboard and monitoring data
- Support official tree inventory work

Field workers are not treated as ordinary paid public users. They are part of the operational deployment.

### Admin

Admins manage the whole system. They can:

- Manage users
- Approve Pro requests
- Review unknown species submissions
- Manage official tree inventory
- View analytics and community structure
- Generate QR labels
- Export reports
- Monitor system activity

## 3. Business Model

TreeTrace uses a freemium and institutional SaaS model.

### Starter / Free

Target users:

- Citizens
- Students
- General public

Included:

- View public map
- Open tree profiles
- Unlimited QR scanning
- 10 AI identifications per day
- 15 unknown species submissions per day

Purpose:

- Public conservation awareness
- Community participation
- User acquisition

### Professional

Target users:

- Active citizen users
- Researchers
- Students
- Environmental volunteers

Suggested price:

- PHP 99 per month

Included:

- 50 AI identifications per day
- 100 unknown species submissions per day
- Priority expert review
- Higher usage allowance

Purpose:

- Recurring revenue from active users
- More serious community participation

### Enterprise / Institutional

Target users:

- LGUs
- Barangays
- DENR offices
- Schools and universities
- Environmental organizations

Suggested price:

- PHP 399+ per month or custom institutional pricing

Included:

- Unlimited AI identification
- Unlimited unknown species submissions
- Field worker accounts
- Admin tools
- Reports and QR tools
- Training and onboarding

Purpose:

- Main revenue source
- City-wide or institution-wide tree monitoring deployment

## 4. Plan Limits

| Feature | Free / Starter | Professional | Enterprise |
|---|---:|---:|---:|
| Public map | Unlimited | Unlimited | Unlimited |
| QR scan | Unlimited | Unlimited | Unlimited |
| Public tree profiles | Unlimited | Unlimited | Unlimited |
| AI identification | 10/day | 50/day | Unlimited |
| Unknown species submission | 15/day | 100/day | Unlimited |
| Official tree inventory | Not allowed | Not allowed | Staff/admin only |
| Reports and admin tools | Not allowed | Not allowed | Included for institution/admin |

Admin and field worker accounts are operational roles, so they are not limited like public citizen accounts.

## 5. Citizen Flow

```text
Open TreeTrace
  ↓
View landing page
  ↓
Sign up / log in as citizen
  ↓
Open public portal
  ↓
Citizen can:
  - View public map
  - Search trees
  - Open public tree profile
  - Scan QR tag
  - Use AI scan
  - Submit unknown species for expert review
```

### Citizen AI Scan Flow

```text
Citizen opens AI Scan
  ↓
System checks daily usage
  ↓
Citizen uploads or captures tree photo
  ↓
Backend checks AI limit
  ↓
If under limit:
  - AI identifies species
  - Result appears
  - Cannot Cut warning appears if endangered/protected
  - AI usage count increases
  ↓
If limit reached:
  - App shows limit message
  - User can open Plans & Pricing
```

### Citizen Unknown Species Flow

```text
AI cannot confidently identify tree
  ↓
Citizen taps Submit for Expert Review
  ↓
Backend checks unknown submission limit
  ↓
Submission is saved as pending review
  ↓
Admin reviews later
  ↓
Admin may identify, close, or use the submission for database improvement
```

## 6. Pro Upgrade Flow

Current implementation uses admin-approved upgrade.

```text
Citizen opens Plans & Pricing
  ↓
Citizen taps Request Pro Upgrade
  ↓
Backend marks account as upgrade_requested
  ↓
Admin sees pending Pro request
  ↓
Admin approves by changing subscription to Pro
  ↓
Citizen refreshes/logs in again
  ↓
Citizen gets Pro limits
```

This is acceptable for prototype and capstone demonstration because it shows the business model and functional subscription logic.

Future payment integration can automate this using:

- PayMongo
- GCash
- Maya
- Stripe

## 7. Field Worker Flow

```text
Field worker logs in
  ↓
Dashboard opens
  ↓
Field worker can:
  - View tree statistics
  - Add official tree records
  - Open map
  - Use AI scan
  - Scan QR from dashboard
  - View community structure
  - View health logs
```

Field workers support official inventory work. They should not go through public Pro limits because they are part of the institution using the system.

## 8. Admin Flow

```text
Admin logs in
  ↓
Dashboard opens
  ↓
Admin can:
  - View total trees, health status, carbon stock
  - Search tree records
  - Scan QR
  - View users
  - View community structure
  - Review unknown species
  - View QR labels
  - View health logs
  - Manage web dashboard tools
```

### Admin Unknown Review Flow

```text
Citizen submits unknown species
  ↓
Admin receives pending notification
  ↓
Admin opens Unknown Review
  ↓
Admin reviews image/details
  ↓
Admin marks as identified or closed
```

### Admin User and Pro Approval Flow

```text
Citizen requests Pro
  ↓
Admin opens user management
  ↓
Admin checks pending request
  ↓
Admin changes subscription plan to Pro
  ↓
Citizen receives higher limits
```

## 9. Public QR Flow

```text
Tree has QR label
  ↓
Citizen or field worker scans QR
  ↓
App opens public tree profile
  ↓
User sees:
  - Common name
  - Scientific name
  - Health status
  - Location
  - DBH and height if available
  - Conservation information
```

QR scanning is unlimited because it supports education and public access.

## 10. Cannot Cut Warning Flow

```text
AI identifies a tree
  ↓
System checks conservation status
  ↓
If endangered/protected:
  - Red Cannot Cut warning appears
  - User is alerted immediately
  - Tree is flagged as conservation-sensitive
```

This feature is important for capstone defense because it shows direct conservation value.

## 11. Community Structure Flow

```text
Admin or field worker opens Community Structure
  ↓
System analyzes tree inventory data
  ↓
Shows:
  - Total trees
  - Total species
  - Endangered count
  - Barangay count
  - Species distribution chart
  - Trees per barangay chart
  - Barangay biodiversity breakdown
```

This supports LGU planning, biodiversity monitoring, and reporting.

## 12. Revenue Streams

### Subscription Revenue

Main recurring revenue from:

- Professional users
- Enterprise / institutional clients

### Institutional Deployment

Higher-value clients:

- LGUs
- Schools
- Barangays
- DENR-related offices
- Environmental organizations

Possible package:

- Monthly subscription
- Setup fee
- Training fee
- Maintenance and support fee

### Training and Onboarding

TreeTrace can charge for:

- Field worker training
- Admin training
- QR tagging workflow setup
- Data migration

### Reports and Analytics

Institutions may pay for:

- Inventory reports
- Tree health reports
- Carbon stock reports
- Barangay biodiversity reports
- QR label generation

## 13. Why This Is Technopreneurship

TreeTrace is not only a monitoring tool. It has a realistic business model:

- Free access creates public adoption.
- Pro access creates individual recurring revenue.
- Enterprise access creates higher-value institutional revenue.
- Community submissions improve the dataset over time.
- Reports, QR labels, and analytics make the system valuable to LGUs and schools.

The system solves a real local problem while also having a path to sustainability.

## 14. Current Prototype Scope

Currently implemented or represented:

- Public landing page
- Web and Flutter login/signup
- Public map
- QR scanning
- AI identification
- Cannot Cut warning
- Unknown species submission
- Unknown review workflow
- Plans and pricing
- Pro request workflow
- Admin/field worker dashboard
- Community structure charts
- Users screen
- QR labels screen
- Health logs viewing

## 15. Future Improvements

Recommended next improvements:

- Add PayMongo, GCash, Maya, or Stripe payment verification
- Add automatic Pro activation after successful payment
- Add full mobile Add Health Log form
- Add print-ready QR label generation in Flutter
- Add PDF export in mobile
- Add route planning for field workers
- Add stronger DBH measurement workflow using circumference or reference-object photo
- Add more DENR/IUCN references
- Add admin notification center
- Add offline sync status page

