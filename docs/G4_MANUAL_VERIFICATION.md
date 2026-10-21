# G4 Manual Verification Checklist — Pending Review and Approval

Scope: `POST/GET /api/tree-submissions/*`, `POST /api/ai/unknown-species/{id}/convert`,
the `/my-submissions` web page, the Flutter **My Submissions** screen, the
citizen AI-Identify/mobile submit paths, migration `0002_add_tree_submissions.sql`,
and the `verify_submission_schema()` startup preflight.

Automated coverage: `backend/tests/test_tree_submission_contracts.py` and
`backend/tests/test_submission_preflight.py` (part of the 220-test suite).
This document covers what tests cannot: real browsers, the Flutter app, and
the PostgreSQL staging phase.

> Rule for every phase: **nothing may modify the official inventory except an
> approved submission or a staff tree record.** If any step silently creates
> or changes a `trees` row, stop and report it.

---

## Part 1 — Website (local dev: backend + `npm run dev`)

### 1.1 Citizen Path A (species known → pending submission)
1. Register a fresh citizen (self-registration always yields `citizen`).
2. Open AI Identify, upload a photo, enter a species name, GPS, barangay.
3. Submit ("Submit for Expert Review"). Expect: toast "Submitted for
   expert review", redirect to **My Submissions** showing the row as
   **Pending Review** with photo, species, coordinates.
4. Confirm the tree does NOT appear in Tree Inventory, Tree Map, Dashboard
   stats, or the CSV export (structural separation).
5. Repeat submit after a forced network failure (dev tools → Offline →
   submit → Online → resubmit): expect exactly ONE pending row (same
   client_uuid retry), quota counted once.

### 1.2 Citizen Path B (species unknown → unknown-species → conversion)
1. As the citizen, submit via AI Identify with NO species name. Expect:
   toast about expert review, no pending tree submission created.
2. As admin, open Unknown Review: the entry is there unchanged. Mark
   *Approve Identification* (enter e.g. "Narra").
3. The new **Create Tree Submission** panel appears. Click it. Expect:
   success toast; the entry itself unchanged; a new pending submission
   with `source=ai_identify`, species = the identified name, original
   submitter preserved.
4. Click Create Tree Submission again. Expect: "already exists" toast, no
   duplicate (replay via unique `source_unknown_species_id`).

### 1.3 Review actions (admin and field worker)
1. As field worker, open the review queue (`GET /api/tree-submissions/` via
   any staff tool) — pending submissions listed newest first.
2. **Reject** with no reason → blocked client- and server-side (422).
   Reject with a reason → status Rejected; citizen sees the exact reason
   and a **Resubmit with Corrections** button (pre-fills AI Identify).
3. **Reopen** the rejected row → back to Pending; previous reason retained
   as history; reviewer cleared.
4. **Approve** a submission missing the species name → 422 asking for
   common_name. Approve again with overrides (species, DBH) → tree
   created; open it: carbon computed server-side, `recorded_by` = reviewer;
   the submission's original fields are unchanged and the overrides are
   visible separately.
5. Approve the same submission a second time → 409 with the existing tree
   id; exactly one tree exists.
6. **Link** flow: create a submission with coordinates near an existing
   tree; as staff use the nearby suggestion, then link to that tree →
   status Linked, tree data untouched, tree count unchanged. Link a SECOND
   submission to the SAME tree → succeeds (safeguard A).
7. Approved and Linked rows: approve/reject/link/reopen all refuse (409).

### 1.4 Self-review prohibition
1. As admin, create a submission (staff may use the same endpoint).
2. Attempt approve/reject/link/reopen on it as the SAME admin → 403
   "You cannot review your own submission."
3. A different staff member can act on it.

### 1.5 Quota
1. As citizen, submit 10 trees (free plan) → all succeed; the 11th → 402
   with the upgrade message; `/api/ai/usage` shows
   `tree_submissions.used_today = 10`.
2. Retry an earlier successful client_uuid while at the limit → 200
   replay, no quota consumed.
3. Admin/field worker: more than 10 submissions in a day → all succeed.

### 1.6 Access control
1. Citizen calls staff endpoints directly (browser dev tools / curl with
   the citizen token): `GET /api/tree-submissions/` → 403;
   approve/reject/link/reopen → 403; convert → 403.
2. Logged-out visitor to `/my-submissions` → redirected to login.
3. Citizen A must never see citizen B's submissions in `/my`.

---

## Part 2 — Flutter app

1. **Citizen gating (requirement 12):** as citizen, open the tree-list FAB
   (Add Tree). Fill the form and save while ONLINE → the save hits the
   SUBMISSION endpoint: snackbar "Submitted for expert review! Track it
   under My Submissions"; the tree does not appear in the citizen map/list.
2. **Online-only (decision 8):** as citizen, enable airplane mode and
   save → snackbar "Tree submissions need an internet connection"; no
   offline queue entry is created for the citizen.
3. **Retry safety (safeguard D):** submit with a connection drop right
   after send (dev tools / toggle airplane mode mid-request) → retry from
   the pending-recovery dialog → exactly one submission server-side.
4. **My Submissions screen:** More → My Submissions (citizen) → list with
   Pending/Approved/Rejected/Linked chips; rejected shows the review
   reason; approved/linked rows link to the tree detail screen; pull to
   refresh works.
5. **Staff unchanged (requirement 13):** as field worker, Add Tree still
   creates official trees with the nearby check, offline queue, evaluation
   row, and all G2 recovery dialogs behaving exactly as before.
6. **Quota surfacing:** at the limit, the mobile submit surfaces the 402
   message text.

---

## Part 3 — Database staging phase (user-performed; NO automated execution)

> Per project rules these are executed by the user against the STAGING copy
> only, after backup, following `backend/migrations/0002_add_tree_submissions.sql`.

1. **Backup:** `pg_dump "$DATABASE_URL" --table=users --table=trees > g4_backup_<date>.sql`
2. **Preflight (read-only):**
   - `SELECT to_regclass('tree_submissions');` → NULL before apply.
   - `SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name='tree_submissions_today';` → 0 rows.
3. **Apply** the migration once per staging database (Render + Vercel
   backings must BOTH be checked for drift; apply to each that lacks it).
4. **Verify properties** (mirrors the startup preflight):
   - `SELECT count(*) FROM information_schema.columns WHERE table_name='tree_submissions';` → 27.
   - `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='tree_submissions'::regclass;` → status CHECK with all four states; UNIQUE on client_uuid and source_unknown_species_id.
   - `SELECT indexname, indexdef FROM pg_indexes WHERE tablename='tree_submissions';` → `ux_tree_submissions_approved` partial `WHERE status = 'approved'`.
   - `SELECT count(*) FROM users WHERE tree_submissions_today IS NULL;` → 0.
5. **Negative preflight test (staging):** deploy the G4 backend against a
   database WITHOUT the migration → it must REFUSE to boot with
   "FATAL: unsafe G4 submission schema: ...". Then apply and confirm both
   log lines: `preflight OK: trees.client_uuid present with unique index`
   and `preflight OK: tree_submissions schema verified`.
6. **Concurrency check (staging, mirrors G2's):**
   ```
   UUID=$(python -c "import uuid;print(uuid.uuid4())")
   PAYLOAD="{\"common_name\":\"Narra\",\"client_uuid\":\"$UUID\"}"
   seq 10 | xargs -P 10 -I{} curl -s -o /dev/null -w "%{http_code}\n" \
     -X POST "$BACKEND_URL/api/tree-submissions/" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d "$PAYLOAD"
   ```
   Expect: one 201, nine 200; `SELECT count(*) FROM tree_submissions WHERE client_uuid='<UUID>';` → 1; the citizen's
   `tree_submissions_today` incremented by exactly 1.
7. **Rollback understanding:** preferred rollback = redeploy the previous
   build, RETAIN the schema (old code ignores the table/column). Dropping
   the table destroys the citizen submission history — read the migration
   header before considering it.

---

## Sign-off matrix

| Area | Verified by | Result |
|---|---|---|
| Backend contracts + concurrency + preflight (220 tests) | automated | |
| Web production build | automated (`npm run build`) | |
| Flutter analyzer (0 errors) | automated | |
| Website Parts 1.1–1.6 | manual | |
| Flutter Parts 2.1–2.6 | manual | |
| Staging DB Parts 3.1–3.7 | manual (user) | |
