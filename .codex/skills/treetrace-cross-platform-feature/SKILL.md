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

- Use `PATCH /api/trees/{tree_id}` for partial tree updates. Do not add a duplicate `PUT` route for a client mismatch unless backward compatibility is explicitly required.
- Compare every affected React and Flutter client with the FastAPI route before considering a cross-platform change complete.

## Tree Measurement Contract

- DBH is measured in centimeters; height is measured in meters.
- For normal tree updates, omit unchanged DBH and height. A supplied measurement must be finite and greater than zero; explicit `null` is not a valid update operation.
- New tree creation may omit or explicitly use `null` for DBH and height because measurements can legitimately be unknown.
- Biomass and carbon are server-owned derived values. Normal React and Flutter tree create/update requests must not submit them as client-controlled values.

## Client Consistency

- React and Flutter must follow the same backend data contract even when their UI implementations differ.
- Treat client validation as UX support; backend validation remains authoritative.
- Inspect actual request payloads. Matching screens do not prove matching API behavior.

## Preserve TreeTrace Rules

- Apply authorization in the backend. UI role checks must not be the only protection.
- Maintain public endpoints under `/api/public` without exposing staff-only or user-sensitive data.
- Keep JWT handling on the shared React Axios client and Flutter `ApiService` paths.
- Preserve the existing mobile user-review-before-sync workflow. Do not silently add offline replay for a new mutation type.
- For a new mobile mutation that needs offline support, explicitly define its queue representation, verification state, retry behavior, upload-failure behavior, and replay endpoint.
- Do not add credentials, production URLs, or service-role keys to source files.

## Public Boundaries

- Keep `/api/public` endpoints and QR/profile flows separate from protected inventory payloads.
- Never expose staff notes, user identity details, secrets, or other protected fields through public tree or profile responses.

## Skill Priority

When skills overlap, TreeTrace domain and inventory rules take precedence over generic frontend optimization guidance.

## Verify the Change

Check the changed route directly, including its expected unauthorized response where access matters. Then run the relevant client checks:

- `npm run lint` and `npm run build` in `frontend/`
- `flutter analyze` and `flutter test` in `mobile/`

When an endpoint changes, explicitly compare the backend with every consuming client before considering the work complete. Flag a client that is not part of the requested delivery instead of silently leaving it incompatible.
