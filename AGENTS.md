# TreeTrace Agent Guide

Read `knowledge.md` before changing a feature that crosses backend, web, and mobile boundaries.

## Ownership and Change Flow

1. Locate the feature's API route under `backend/app/api/routes/` and identify the associated schema, model, and service.
2. Find every consuming web module under `frontend/src/api/` and page/component under `frontend/src/`.
3. For mobile-facing features, trace the matching method in `mobile/lib/services/api_service.dart`, its model, and its screen.
4. Make the smallest coherent change across all affected layers.
5. Run the relevant verification commands and manually check authorization and error paths when they are affected.

## Backend Rules

- Keep request and response contracts in `app/schemas/`; use the models for persistence behavior.
- Protect all non-public routes with `get_current_user` or a stricter authorization dependency. Keep admin-only actions behind `require_admin`.
- Preserve the public routes under `/api/public` as unauthenticated; do not expose sensitive user data through them.
- Do not rely on client role checks for security. Enforce every role restriction at the route layer.
- Maintain tree invariants: keep calculated carbon/biomass behavior consistent, preserve the health-log-to-tree status update, and treat tree deletion as a cascading action.
- Use existing storage and AI service abstractions. Never embed credentials in source code.
- Database startup currently uses `Base.metadata.create_all` plus PostgreSQL-specific synchronization. Treat schema changes as deployment-sensitive and verify them against the active database provider.

## Web Rules

- Use the shared Axios client in `frontend/src/api/client.js` so JWT attachment and 401 handling stay consistent.
- Add API calls to the relevant module in `frontend/src/api/` instead of issuing duplicate requests directly from pages.
- Keep protected routes inside the existing `ProtectedRoute` and `AppLayout` structure; public views belong outside it.
- Preserve accessibility and existing component patterns, including the established Radix/shadcn-style UI components and Tailwind utilities.

## Mobile Rules

- Route requests through `ApiService`; keep token storage and 401 behavior intact.
- Preserve the review-before-sync rule for offline actions. Do not turn connectivity changes into automatic record submission.
- When adding a mutating mobile action, decide whether it must be queued offline and make its payload compatible with the backend schema.
- Verify HTTP methods exactly. In particular, the backend currently updates trees with `PATCH`, while Flutter's `updateTree` uses `PUT`; resolve or avoid that mismatch when touching mobile tree updates.

## Data and Privacy Rules

- Validate names, measurements, locations, and dates at the appropriate boundary. Do not silently coerce missing or invalid inventory data into misleading records.
- Preserve the connection between health logs and their parent tree.
- Treat public QR pages as publicly readable. Do not add email addresses, tokens, internal notes, or staff-only records to public responses.
- Keep `.env` files, secrets, service-role keys, private database URLs, and generated local artifacts out of commits.

## Verification

- Backend: start the API and exercise the changed route, including unauthorized and authorized paths when permissions change.
- Web: run `npm run lint` and `npm run build` in `frontend/`.
- Mobile: run `flutter analyze` and `flutter test` in `mobile/`.
- Cross-platform: compare endpoint path, HTTP method, request keys, response shape, and error codes across the backend and every affected client.

Preserve unrelated work in the branch. Do not delete files, data, migrations, or model assets merely to make the working tree appear clean.
