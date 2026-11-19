# Panabo inventory boundary enforcement

The backend checks submitted tree coordinates against the bundled Panabo
barangay polygons. Client-supplied city names and a broad bounding rectangle
cannot establish that a location is inside the inventory area.

- New official trees require both coordinates inside Panabo.
- PATCH requests changing coordinates or GPS accuracy validate the merged
  stored and supplied location before changing the row. Coordinates cannot
  be removed to bypass validation. Location edits clear stale accuracy.
- Pending submissions with coordinates are checked before quota use.
  Photo-only evidence may remain pending, but approval requires valid GPS.
- Approval checks the effective location after reviewer overrides, including
  legacy submissions. Reviewers can supply or correct coordinates in the web
  approval dialog without rewriting original submission evidence.
- Unknown-species numeric `lat, lng` descriptions are checked at submission
  and conversion. Ordinary landmark prose remains review evidence, not GPS.
- A point outside Panabo, an incomplete pair, or an uncertainty area crossing
  a barangay/city boundary returns HTTP 422 before any inventory insert.
  Missing or unusable boundary data returns HTTP 503; no approximate fallback
  silently permits a write. No external boundary service is required to save.
- Manual coordinates with no accuracy are checked as points. The server does
  not invent a GPS accuracy estimate.

Already-saved records are not deleted or moved. Read-only idempotent replays
still acknowledge existing records, and unrelated legacy health/notes edits
remain available. New positions and approvals always use the new checks.

Web and Android offline queues already retain HTTP 422 failures for review;
they are not silently discarded or automatically resubmitted. Existing apps
receive the server enforcement after backend deployment; the new coordinate
editor also requires deployment of the web frontend.
