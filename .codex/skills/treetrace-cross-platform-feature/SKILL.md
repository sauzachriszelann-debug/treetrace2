---
name: treetrace-cross-platform-feature
description: Implement or change a TreeTrace feature that crosses the FastAPI API, React web app, and Flutter mobile app. Use when a shared endpoint, user workflow, or response contract affects more than one client.
---

# TreeTrace Cross-Platform Feature

Use this skill for TreeTrace changes that affect two or more of the backend, web app, and mobile app. It does not apply to a self-contained change in only one layer.

## Trace the Contract

Before editing, locate:

1. The backend route in `backend/app/api/routes/`, its request/response schema, and associated model or service.
2. The React request module in `frontend/src/api/` and all pages or components that use it.
3. The Flutter method in `mobile/lib/services/api_service.dart`, its model, and affected screens.

Treat the FastAPI route and Pydantic schema as the API contract. Keep the endpoint path, HTTP method, payload keys, response shape, and error behavior aligned across each affected client.

## Preserve TreeTrace Rules

- Apply authorization in the backend. UI role checks must not be the only protection.
- Maintain public endpoints under `/api/public` without exposing staff-only or user-sensitive data.
- Keep JWT handling on the shared React Axios client and Flutter `ApiService` paths.
- For mobile mutations, decide whether the record must support the existing offline queue and user-review-before-sync flow.
- Do not add credentials, production URLs, or service-role keys to source files.

## Verify the Change

Check the changed route directly, including its expected unauthorized response where access matters. Then run the relevant client checks:

- `npm run lint` and `npm run build` in `frontend/`
- `flutter analyze` and `flutter test` in `mobile/`

When an endpoint changes, explicitly compare the backend with every consuming client before considering the work complete. Flag a client that is not part of the requested delivery instead of silently leaving it incompatible.
