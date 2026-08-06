# API Subdomain Route Isolation

## Goal

Requests to the `api` subdomain must only match routes explicitly declared inside an `api` subdomain constraint. The API host root (`/`) is the sole exception and redirects with HTTP 302 to the normal-site root URL. Any other path must return HTTP 404, even when that path is a valid browser, operational, webhook, or callback route on the normal host.

## Current behavior

Most shared and browser routes are declared before the API-only routes. Because Rails evaluates routes in declaration order, an API-host request such as `GET /login` matches `sessions#new` and returns 200 before routing reaches the API constraints.

## Design

Move the existing API-subdomain route blocks ahead of every route that is not available on the API host. Immediately after the API routes, add API-subdomain-only handling that redirects `GET /` with HTTP 302 to `root_url` on the normal host, with the `api` subdomain removed, then returns the application's existing 404 response for every other method and path. Keep all shared and browser routes after this handling.

Valid API paths continue to reach their current controllers. The existing `/v1/*` compatibility route remains ahead of the fallback and continues returning 410. Other route names, paths, controllers, and API authentication behavior do not change.

## Error handling

The root redirect must build the destination for the normal host rather than reusing the API request host, which would create a redirect loop. The fallback uses the existing not-found handling and returns HTTP 404. It does not redirect, authenticate, or fall through to a route intended for another host.

## Tests

Add integration-level routing coverage using `api.example.com`. The tests will prove that:

- `GET /v2/authentication` still reaches the API stack and returns its existing unauthenticated response;
- `GET /login` and `GET /health_check` return 404 on the API host;
- `GET /` on the API host redirects with 302 to `http://example.com/`;
- an unknown path returns 404 on the API host;
- `GET /health_check` remains available on `www.example.com`; and
- the legacy `/v1/anything` fallback still returns 410.

Implementation will follow test-driven development: add the isolation test first, confirm it fails because a shared route is selected, make the smallest route-ordering change, then run focused and broader routing/controller tests.

## Scope

This change only isolates the existing `api` subdomain. It does not add API endpoints, change response payloads for valid endpoints, alter controller-level authentication, or reorganize unrelated routes.
