# API Subdomain Route Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict the `api` subdomain to its explicitly declared API routes, redirect its root to the normal-site root with HTTP 302, and return HTTP 404 for every other route.

**Architecture:** Preserve all existing API declarations, but move them to the start of the Rails route set so they are evaluated before shared routes. Follow them with an API-host root redirect and catch-all 404; shared routes remain unchanged and are evaluated only after API-host requests have already terminated.

**Tech Stack:** Ruby, Rails routing, Action Dispatch integration tests, Minitest

## Global Constraints

- `GET /` on the `api` subdomain redirects with HTTP 302 to the same request's scheme, registrable domain, and port without the `api` subdomain.
- Routes not explicitly declared for the `api` subdomain return HTTP 404 there, including browser, operational, webhook, and callback routes.
- Existing API endpoints, authentication behavior, route helpers, and the authenticated `/v1/*` HTTP 410 compatibility response remain unchanged.
- Shared routes retain their existing behavior on non-API hosts.

---

### Task 1: Isolate the API route set

**Files:**
- Create: `test/integration/api_subdomain_routes_test.rb`
- Modify: `config/routes.rb:4-410`

**Interfaces:**
- Consumes: Rails' `constraints subdomain: "api"`, `redirect`, wildcard routing, and `ErrorsController#not_found`.
- Produces: API-host routing behavior at the existing route-set boundary; no new Ruby method or public API.

- [ ] **Step 1: Write the failing integration tests**

```ruby
require "test_helper"

class ApiSubdomainRoutesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
  end

  test "serves an existing API route" do
    get "/v2/authentication"

    assert_response :unauthorized
  end

  test "does not serve browser routes" do
    get "/login"

    assert_response :not_found
  end

  test "does not serve operational routes" do
    get "/health_check"

    assert_response :not_found
  end

  test "redirects the API root to the normal host" do
    get "/"

    assert_redirected_to "http://example.com/"
    assert_response :found
  end

  test "returns not found for an unknown path" do
    get "/not-an-api-route"

    assert_response :not_found
  end

  test "preserves the legacy API response" do
    user = users(:ben)
    authorization = ActionController::HttpAuthentication::Basic.encode_credentials(user.email, default_password)

    get "/v1/anything", headers: {"Authorization" => authorization}

    assert_response :gone
  end

  test "keeps shared routes available on the normal host" do
    host! "www.example.com"

    get "/health_check"

    assert_response :ok
  end
end
```

- [ ] **Step 2: Run the integration test and verify the expected failures**

Run: `bin/rails test test/integration/api_subdomain_routes_test.rb`

Expected: the browser-route test reports 200 instead of 404, the operational-route test reports 200 instead of 404, and the root test redirects to `http://api.example.com/login` instead of `http://example.com/`. Existing API, unknown-path, legacy API, and normal-host tests pass.

- [ ] **Step 3: Reorder the existing API routes and add the host boundary**

Move both existing `constraints subdomain: "api"` blocks, without changing their contents or relative order, from their current position to immediately inside `Rails.application.routes.draw do`. Place this boundary directly after them and before `root to: "site#index"`:

```ruby
  constraints subdomain: "api" do
    get "/", to: redirect(status: 302) { |_params, request|
      Rails.application.routes.url_helpers.root_url(
        host: request.domain,
        protocol: request.protocol,
        port: request.port
      )
    }
    match "*path", to: "errors#not_found", via: :all
  end
```

The explicit API routes remain first, `GET /` then redirects to the normal host, and the wildcard prevents all remaining API-host requests from reaching shared routes.

- [ ] **Step 4: Run the focused test and verify it passes**

Run: `bin/rails test test/integration/api_subdomain_routes_test.rb`

Expected: 7 tests pass with no failures or errors.

- [ ] **Step 5: Run relevant routing and controller regressions**

Run: `bin/rails test test/integration test/controllers/api test/controllers/errors_controller_test.rb test/controllers/sessions_controller_test.rb`

Expected: all tests pass with no failures or errors.

- [ ] **Step 6: Check route-file integrity**

Run: `bin/rails routes > /dev/null && git diff --check`

Expected: route loading succeeds and Git reports no whitespace errors.

- [ ] **Step 7: Commit the implementation**

```bash
git add config/routes.rb test/integration/api_subdomain_routes_test.rb
git commit -m "Isolate routes on API subdomain"
```
