# Web gallery DBH, height and age

AI Identify and Add Tree share TreeForm. Selecting an image identifies species
and independently requests `/api/ai/gallery-size-prediction`. The read-only
prediction card shows the original photo, YOLO overlay, predicted DBH/height and
`/api/ai/estimate-age` result. Images can be expanded. Age follows mobile's
DBH-first headline, height cross-check, source distinction, and uncertainty.

When the tip is cropped, **Add treetop photo** sends the same original `file`
plus optional `treetop_file` to the gallery endpoint. The backend must match
the same tree and see its top. The browser accepts only a validated response
contract and updates height only, preserving original DBH/species/overlay.
The age cross-check refreshes using the form's current DBH/height. Photos from separate viewpoints do not establish
metric scale; these remain unvalidated visual predictions.

On user request, gallery analysis now fills empty or previously AI-filled DBH
and height inputs. User edits and existing manual measurements are preserved.
Selecting/removing a photo clears only values still belonging to the prior AI
result. On Save, dimensions are included in the normal inventory/offline payload;
notes identify AI-filled sizes as unvalidated estimates. Carbon based on those
sizes is labeled approximate. The Manual DBH Calculator and Advanced photo
measurement panels are removed; inputs remain editable and the separate height
calculator remains available. Detailed uncertainty and age disagreement are
available under Analysis details / Calculation details rather than repeated
beside the headline. Main dimension labels are DBH and Height.

YOLO retries the lower scene and then two closer central/lower crops, at its
existing trained confidence and input size. Only real masks are mapped back to
original coordinates. No model detection is fabricated; a miss exposes Retry
trunk detection and continues the explicitly AI-estimated size flow.

All calls use the existing authenticated Axios client. New photo selection,
removal and unmount discard stale results. Canceled/error supplemental uploads
keep original results and can be replaced. Images for prediction are bounded to
1.8 MB each without replacing the original inventory upload. No new backend,
database migration or model is required beyond backend commit 53650cba.

## Backend configuration

The browser keeps its existing relative `/api` client and JWT handling.
`frontend/vercel.json` now proxies API calls to the tested backend deployment
used by the phone:
`https://treetrace2-backend-3rwyf5f9x-sauzachriszelann-debugs-projects.vercel.app`.
This includes authentication, so the web does not mix different backend
deployments for login and prediction. The proxy avoids introducing direct
cross-origin browser API calls. Update all API destinations together when
switching to a production backend that includes these features.

For local development use the existing relative `/api` Vite proxy:

```powershell
$env:VITE_API_PROXY_TARGET='https://treetrace2-backend-3rwyf5f9x-sauzachriszelann-debugs-projects.vercel.app'
npm run dev
```

## Verification

`npm test` covers API multipart fields, species/size/age races, source labels,
treetop mismatches and height-only updates, full-photo dialog, and the inventory
submission boundary. Run `npm run lint` and `npm run build` as well.

In browser, test a full tree, a cropped top with matching second view, a different
tree as the second view, changing the original during requests, and a failed
request/retry. Confirm inventory measurement inputs stay manual and the age
source link opens the appropriate published study when present.
