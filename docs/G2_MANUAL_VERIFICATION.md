# G2 Manual Verification Checklist — Pending Submission Safety

Scope: the corrected idempotency flows on web (`AddTree.jsx`, `AIIdentify.jsx`
staff path) and mobile (`add_tree_screen.dart`, `api_service.dart`). No automated
client test infrastructure exists, so G2 closure requires this manual pass on real
builds against a **staging** backend with migration 0001 applied.

Conventions:
- **Key** = `client_uuid` submission key.
- **Original** = `original_payload` (web) / `submitted_payload` (mobile): the first
  payload sent under a key that may have reached the server.
- Pass criteria are stated per step. Any deviation is a G2 blocker.

Prerequisites:
1. Staging backend with `0001_add_trees_client_uuid.sql` applied and the log line
   `preflight OK: trees.client_uuid present with unique index`.
2. An admin or field-worker account (citizens cannot create inventory trees).
3. Browser dev tools open (Application → Session Storage) on web; a device or
   emulator with the mobile build installed.
4. A network-throttling tool (dev tools "Offline"/"Slow 3G", or a firewall rule
   to simulate timeouts).

---

## Web — AddTree (repeat identical steps on AIIdentify staff path)

### W1. Successful 201
1. Fill a valid tree and Save.
- Pass: record page opens; sessionStorage draft key removed; one row in
  inventory; server row's `client_uuid` equals the generated key (check via API
  or DB read-only query).

### W2. HTTP 200 idempotent replay
1. Before step W1's response returns (throttle to Slow 3G), double-click Save.
- Pass: exactly one row; the second response is a 200 replay (banner or
  navigation, never a duplicate).

### W3. Timeout → uncertain → Retry Original
1. Set network Offline in dev tools; Save.
- Pass: error toast "Connection problem - your submission is saved"; banner
  shows "A previous save may have reached the server" with buttons
  **Retry Original Submission**, **Resume & Edit**, **Discard**; sessionStorage
  draft has `status: "uncertain"` and an `original_payload`.
2. Restore network; click **Retry Original Submission**.
- Pass: exactly one row created under the same key; draft cleared.

### W4. Timeout → Resume & Edit (Save Edited Submission)
1. Repeat W3 step 1 (go Offline, Save).
2. Go online; click **Resume & Edit**; change `dbh_cm` only; Save.
- Pass: request carries the SAME key; because the first attempt never landed you
  get a 201; draft cleared.
3. Repeat with the first attempt landing (Slow 3G, refresh after ~2s, then
   resume-edit and Save).
- Pass: 200 replay with `replayed_differences` shown; stored tree unchanged;
  `original_payload` in the draft (before success) still the FIRST payload.
4. Variant: while uncertain, resume-edit and Save while still Offline.
- Pass: draft becomes uncertain again, `original_payload` is still the first
  payload (not the edited one) and **Retry Original Submission** still appears.

### W5. Identity change → Start New Submission (never automatic)
1. With an uncertain draft present, fill the form with a DIFFERENT
   common_name/coords (or use a fresh form on the same tab) and Save.
- Pass: no request is sent; panel "This form looks like a different tree"
  appears with **Start New Submission** and **Keep Pending Submission**.
2. Click **Keep Pending Submission**.
- Pass: panel closes; sessionStorage draft (key + original_payload) unchanged.
3. Save again; click **Start New Submission**.
- Pass: only NOW is a new key generated; old draft cleared by that click only.

### W6. HTTP 409 conflict
1. In dev tools, edit the draft's `snapshot` to a different identity than the
   stored tree while keeping the key, then Save (or replay a known conflicting
   key via console).
- Pass: red conflict panel; nothing merged; **Start new submission** clears the
  draft only when clicked; **Open existing record** keeps the draft.

### W7. HTTP 422 validation error
1. Temporarily break a field client-side (e.g. via console set an out-of-range
   coordinate the form validation misses) and Save.
- Pass: field-error toast; draft becomes `status: "draft"`;
   `original_payload` is dropped ONLY if no earlier unresolved send exists for
   that key; the key is retained.

### W8. Refresh / restart
1. During an uncertain state (W3 step 1), press F5.
- Pass: banner reappears with the same key and `original_payload` intact and
  the Retry Original button present. Closing the tab discards it — this is the
  accepted sessionStorage limitation (documented).

### W9. Offline queue (Field Sync)
1. Verify a `CREATE_TREE` queue item exists with `client_uuid` in its payload
   (currently no web producer enqueues these; test only if a producer is added).
- Pass: failed syncs keep the item; successful syncs post the same payload and
  key; a re-sync after a lost response yields a 200 replay, not a duplicate.

---

## Mobile — AddTreeScreen

### M1. Successful 201
1. Fill a valid tree; Save online.
- Pass: screen pops; pending-draft key removed from secure storage; one row.

### M2. Timeout → uncertain → Retry Original
1. Enable airplane mode; Save.
- Pass: snackbar "Connection problem - your submission is saved..."; on next
  app launch the recovery dialog offers **Retry original submission** (envelope
  `status: uncertain` with `submitted_payload`).
2. Disable airplane mode; tap **Retry original submission**.
- Pass: one row under the same key; envelope cleared.

### M3. Restart mid-flight
1. Airplane mode; Save; force-kill the app; relaunch.
- Pass: recovery dialog shows the same key and data; Resume restores the form;
  Retry Original sends the stored payload verbatim (photo URL reused — verify
  no second photo upload in server logs).

### M4. Resume, edit, identity preserved
1. Recover a draft; change `dbh_cm`; Save.
- Pass: same key reused; `submitted_payload` in the envelope is still the FIRST
  sent payload if an earlier attempt was unresolved (check via a second
  airplane-mode save after the edit: the envelope keeps the original).

### M5. Identity change → explicit confirmation only
1. Recover a draft; change common_name to a different tree; Save.
- Pass: "Start a new submission?" dialog appears; **Keep pending submission**
  aborts the save with key + payload intact; **Discard & start new** clears and
  generates a new key.
2. Dismiss the recovery dialog at launch; fill a fresh form; Save.
- Pass: the same confirmation dialog appears (the stored envelope is never
  silently replaced).

### M6. HTTP 409 shown as conflict
1. Force a 409 (edit a stored key's identity server-side or replay a known
   conflicting key via a debug build).
- Pass: from Save — the "This key belongs to a different tree" dialog; from
   Retry Original — the "Submission conflict: ..." snackbar. NEVER the
   "Connection problem" wording. Dismissing either dialog keeps the envelope.

### M7. Offline queue hand-off
1. Airplane mode; Save.
- Pass: "Saved offline..." snackbar; queue entry contains the same
   `client_uuid`; sync (Field Sync → verify → upload) creates one row; a
   repeated sync after a forced network drop re-posts the same payload and gets
   a replay; the uploaded photo URL is persisted in the queue item (no second
   photo upload in server logs).

### M8. Unreadable / inaccessible secure storage (engineering QA)
Simulate with a temporary debug override in `ApiService` that throws from
`_storage.read` (storage case) or returns a non-JSON string (unreadable case).
1. Storage failure at launch.
- Pass: "Could not check secure storage... Nothing was discarded." and the app
  continues; no key is generated silently on save — the "Unreadable pending
  submission" dialog blocks the save until the user picks
   **Cancel (keep pending data)** or **Overwrite & Start New**.
2. Unreadable JSON at launch.
- Pass: "Previous submission could not be read" dialog showing the raw stored
  bytes with **Keep It** / **Discard Unreadable Draft**; nothing is deleted
  unless the second is tapped.
3. Storage failure while recording an uncertain result.
- Pass: "Could not update the saved submission... Nothing was deleted." and the
  stored envelope is left byte-for-byte untouched.

---

## Cross-cutting checks (both platforms)
- C1. Server-side: after every scenario, `SELECT client_uuid, count(*) FROM
  trees GROUP BY 1 HAVING count(*) > 1` returns zero rows.
- C2. A replayed submission never changes stored values (compare before/after).
- C3. No flow generates a new `client_uuid` while a submission is unresolved
  unless the user pressed an explicit Start New / Discard confirmation.
- C4. Legacy clients (no `client_uuid`) still behave exactly as before
  (two identical POSTs create two trees).
