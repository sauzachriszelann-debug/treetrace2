# G3 Manual Verification Checklist — Nearby Tree Matching Suggestions

Scope: `GET /api/trees/nearby` plus the advisory gates in web (`AddTree.jsx`,
`AIIdentify.jsx` staff path) and mobile (`add_tree_screen.dart`). Backend
behavior is covered by automated tests (`test_tree_nearby_contract.py`); this
checklist covers the client flows and cross-cutting guarantees that need a
running backend (local dev or staging) and real devices.

Conventions:
- **Candidate** = an existing tree returned by the nearby check.
- **Gate** = the explicit "Register as a new tree anyway" / "Register as a
  new tree" confirmation that appears when candidates exist.
- Prerequisites: backend running with test data; an admin and a field-worker
  account; a citizen account; browser dev tools; emulator + one physical
  device for mobile.

---

## Web — AddTree (repeat on AIIdentify staff path)

### W1. Candidates found → gate shown
1. Create a seed tree at a known GPS point (or use an existing one).
2. Start a new registration ~10 m from it with GPS captured, same or
   different species, and Save.
- Pass: "Possible existing trees nearby" panel appears with the candidate's
  name, approximate distance, species-match label, barangay, and a working
  "View record" link; **no POST is sent** until the gate is answered.

### W2. Gate — Cancel
1. Repeat W1; click **Cancel** in the panel.
- Pass: "Registration stopped. Nothing was submitted." toast; no row created;
  form values intact; sessionStorage draft untouched (no key was consumed).

### W3. Gate — Register anyway
1. Repeat W1; click **Register as a new tree anyway**.
- Pass: exactly one new row (HTTP 201); it navigates to the new record; the
  existing candidate is unchanged (`GET` it and compare).

### W4. No candidates → normal submission
1. Register a tree >100 m (and one 60 m) from any existing tree.
- Pass: 60 m with default radius 15 m → no gate, normal 201; no nearby UI.

### W5. Missing GPS → no check, no block
1. Clear lat/lng in the form and Save.
- Pass: no nearby request (dev tools network tab); normal submission flow.

### W6. Failed check is never "no matches" (G3-B)
1. Break the API (dev tools: block `/api/trees/nearby`, or stop the backend)
   and Save a valid new submission.
- Pass: "The nearby check could not be completed" panel with an explicit
  **Continue without nearby check** button; the flow does NOT auto-proceed;
  Cancel leaves nothing submitted. After restoring the network, Save again
  and confirm the check works (W1).

### W7. Timeout does not hang
1. Throttle the nearby request beyond the 5 s client timeout and Save.
- Pass: the W6 failure panel appears within seconds; the save button is not
  stuck disabled afterwards.

### W8. G2 same-key flows skip the check
1. With a pending uncertain submission present (see G2 checklist W3), use
  **Retry Original Submission**.
- Pass: no nearby request at all.
2. Resume & Edit the same pending draft, change only `dbh_cm`, Save.
- Pass: no nearby request; same key reused (G2 behavior unchanged).

### W9. Start New after a conflict/replacement still checks
1. With a pending draft for a different identity, submit and confirm
   **Start New Submission** at a location near an existing tree.
- Pass: the nearby gate appears after the Start-New confirmation (new
  submission path), before the POST.

### W10. Role gating
1. Call `/api/trees/nearby` with a citizen token (curl or dev tools).
- Pass: HTTP 403.

## Mobile — add_tree_screen (physical device for M4/M5)

### M1. Candidates found → dialog, tap opens record
1. New submission ~10 m from an existing tree, online.
- Pass: "Possible existing trees nearby" dialog lists name, distance,
  species-match label, barangay; tapping a candidate opens
  `TreeDetailScreen` for that tree; Cancel aborts the save with nothing
  written (no pending envelope created).

### M2. Register as a new tree
1. Repeat M1; tap **Register as a new tree**.
- Pass: one new row; existing record untouched.

### M3. No candidates / missing GPS
1. Save far from any tree → normal save, no dialog. Save with GPS denied or
   empty → no dialog, normal save (missing GPS must never block).

### M4. Offline save skips the check, limitation stated
1. Airplane mode; save a new tree with GPS present.
- Pass: no nearby request; "Saved offline - the nearby duplicate check was
  skipped..." snackbar; queue entry still carries `client_uuid` (G2
  unchanged); Field Sync upload works as in G2 checklist M7.

### M5. Failed check requires explicit continue (G3-B)
1. Online but with `/trees/nearby` failing (backend proxy rule, or firewall
   the path on the device) and save a new tree.
- Pass: "Nearby check could not be completed" dialog; **Continue without
  check** proceeds; Cancel aborts with nothing written; never treated as
  zero matches.

### M6. G2 same-key flows skip the check (mobile)
1. Retry Original from the recovery dialog; and resume+edit a pending draft
   changing only a measurement.
- Pass: no nearby dialog in either flow; key/payload behavior unchanged.

## Cross-cutting
- C1. **Read-only:** nearby responses change nothing — repeat any scenario
  and verify the trees table/records are byte-identical (compare before/
  after via GET, not DB writes).
- C2. **No auto-merge/reject:** in every gate scenario, choosing Cancel or
  closing the app never modifies, merges, deletes, or rejects any record.
- C3. **Response minimization:** the nearby payload contains no `lat`/`lng`
  or `photo_url` (automated test pins the shape; spot-check in dev tools).
- C4. **Server contract:** with >50 trees planted inside the box, the API
  still returns the true nearest five in order (automated regression test
  `test_nearby_orders_correctly_with_more_than_fifty_candidates`).
