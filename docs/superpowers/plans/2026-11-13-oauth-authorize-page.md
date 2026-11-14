# OAuth Authorize Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/oauth/authorize` is one purpose-built page that signs in and authorizes in a single step, with clear consent copy, and works well on a phone with the keyboard up.

**Architecture:** Doorkeeper's stock `AuthorizationsController` is left untouched. A small `Oauth::BaseController` becomes Doorkeeper's `base_controller` (skips the app's `authorize` filter, holds layout and scope assignment) and its `oauth_resource_owner` method is what the `resource_owner_authenticator` block calls. Views are ours.

**Tech Stack:** Rails, Doorkeeper 5.9, Minitest integration tests, Tailwind, ERB.

**Spec:** `docs/superpowers/specs/2026-11-13-oauth-authorize-page-design.md`

## Global Constraints

- No subclass of, `class_eval` into, or call to private methods of Doorkeeper's controllers.
- An invalid client or redirect URI renders the error page and never redirects, signed in or out.
- A failed sign-in keeps every OAuth parameter.
- No grant without a button press.
- Before controller or route work, use the `rails-conventions` skill; before writing or changing tests, use the `test-audit` skill.
- Run tests with `source ~/.bash_profile && bundle exec rails test <file>`; the full suite is `source ~/.bash_profile && bundle exec rake`.
- Commit messages follow the branch's style (a sentence describing the behaviour). No `Co-Authored-By`.
- Don't start a server. The site is at `https://feedbin.resolv.app`; restart with `rails restart`.

## Review Focus

- Unknown email, or blank password: same "Invalid email or password" as a wrong password, no sign-in. (Task 1)
- Signed-out GET with an unregistered `redirect_uri`: error page, no sign-in form, no redirect. (Task 1)
- Signed-out Cancel: redirects to the app with `error=access_denied` and the original `state`. (Task 1)
- Failed sign-in with a `state` containing `&`, `=` and spaces: `state` round-trips unchanged. (Task 1)
- "Not you?" with an unregistered `redirect_uri`: lands on the error page, not an off-site redirect. (Task 2)

## File Structure

- Create `app/controllers/oauth/base_controller.rb`: base for Doorkeeper's HTML controllers; who the resource owner is.
- Create `app/controllers/oauth/sessions_controller.rb`: "Not you?" sign-out.
- Create `app/views/layouts/oauth_page.html.erb`: top-aligned mobile layout for the OAuth pages.
- Modify `config/initializers/doorkeeper.rb`, `config/routes.rb`.
- Rewrite `app/views/doorkeeper/authorizations/new.html.erb`; modify `error.html.erb` to use the new layout.
- Modify `test/integration/oauth_authorization_test.rb`.

---

### Task 1: Sign in and authorize in one request

**Files:**
- Create: `app/controllers/oauth/base_controller.rb`
- Modify: `config/initializers/doorkeeper.rb`
- Modify: `app/views/doorkeeper/authorizations/new.html.erb` (minimum to work signed out; Task 3 finishes it)
- Test: `test/integration/oauth_authorization_test.rb`

**Interfaces:**
- Produces: `Oauth::BaseController < ApplicationController` with
  - `OAUTH_PARAMS = %i[client_id redirect_uri state response_type response_mode scope code_challenge code_challenge_method]`
  - private `oauth_resource_owner -> User | nil` (may redirect or render 404)
  - private `authorization_params -> Hash` (the `OAUTH_PARAMS` slice of `params`, permitted)
  - private `assign_v3_scopes` (moved from the initializer unchanged)
- Flash keys on a failed sign-in: `flash[:error]` (message), `flash[:email]` (the submitted email).
- Form fields the view posts: `email`, `password`, plus `OAUTH_PARAMS`.

- [ ] **Step 1: Confirm the assumption.** In `config/initializers/doorkeeper.rb` temporarily make the authenticator return `nil` for signed-out requests, add `skip_before_action :authorize` via the existing `class_eval`, and run a signed-out `GET` and `DELETE` of `oauth_authorization_path(authorize_params)` from a scratch test. Expected: GET reaches the `new` template (it will raise on `current_user.email`, which is fine), DELETE redirects to `myreader://oauth/callback?error=access_denied...`. If Doorkeeper refuses a nil owner, **stop and report**; do not fall back to subclassing. Revert the temporary edits.

- [ ] **Step 2: Write the failing tests.** Replace `"sends a signed out user to the login form"` and add, in `test/integration/oauth_authorization_test.rb`:

```ruby
test "a signed out visitor sees the authorize page without a redirect or notice" do
  get oauth_authorization_path(authorize_params)

  assert_response :success
  assert_select "input[name=email]"
  assert_select "input[name=password]"
  assert_select "button", text: "Sign in and authorize"
  refute_includes response.body, "Please sign in."
end

test "signing in on the authorize page authorizes and signs in to Feedbin" do
  post oauth_authorization_path, params: authorize_params.merge(email: @user.email, password: default_password)

  location = URI(response.location)
  assert_equal "myreader", location.scheme
  assert Rack::Utils.parse_query(location.query)["code"].present?

  get oauth_authorization_path(authorize_params)
  assert_select "input[name=password]", count: 0
  assert_select "button", text: "Authorize"
end

test "a wrong password returns to the authorize page with every parameter kept" do
  state = "a b&c=d"
  post oauth_authorization_path, params: authorize_params.merge(state: state, email: @user.email, password: "nope")

  assert_redirected_to oauth_authorization_path(authorize_params.merge(state: state))
  follow_redirect!
  assert_includes response.body, "Invalid email or password"
  assert_select "input[name=email][value=?]", @user.email
  assert_select "input[name=state][value=?]", state
  assert_equal 0, Doorkeeper::AccessGrant.count
end

test "an unknown email or blank password is refused the same way" do
  [{email: "nobody@example.com", password: default_password}, {email: @user.email, password: ""}].each do |credentials|
    post oauth_authorization_path, params: authorize_params.merge(credentials)
    follow_redirect!
    assert_includes response.body, "Invalid email or password"
  end
end

test "an account without API v3 is not signed in" do
  other = users(:ann)
  post oauth_authorization_path, params: authorize_params.merge(email: other.email, password: default_password)

  follow_redirect!
  assert_includes response.body, "This account can’t connect apps yet"
  assert_select "input[name=password]"
end

test "a signed out visitor can cancel" do
  delete oauth_authorization_path, params: authorize_params

  query = Rack::Utils.parse_query(URI(response.location).query)
  assert_equal "access_denied", query["error"]
  assert_equal authorize_params[:state], query["state"]
end

test "an unregistered redirect URI shows the error page to a signed out visitor" do
  get oauth_authorization_path(authorize_params.merge(redirect_uri: "https://evil.example/cb"))

  assert_includes response.body, "This app can’t connect to Feedbin"
  assert_select "input[name=password]", count: 0
end
```

Check `authorize_params` in the file includes a `state`; add one if not. Confirm `users(:ann)` does not have `api_v3` on, or pick a fixture that doesn't. Keep the existing test `"a new user signs up and comes back to the authorization screen"` passing: it depends on `store_location`, which Step 4 preserves.

- [ ] **Step 3: Run to verify they fail.** `source ~/.bash_profile && bundle exec rails test test/integration/oauth_authorization_test.rb`. Expected: the new tests fail (redirect to `/login`).

- [ ] **Step 4: Implement `Oauth::BaseController`.**
  - `skip_before_action :authorize`, `layout false`, `before_action :assign_v3_scopes, only: [:new, :create]`.
  - `oauth_resource_owner`:
    - signed in: `require_api_v3`, then `current_user unless performed?` (today's behaviour).
    - signed out, not POST: `store_location`, return `nil`.
    - signed out, POST: find by `params[:email]` and `authenticate(params[:password])` exactly as `SessionsController#create` does. On failure set `flash[:error] = "Invalid email or password"` and `flash[:email]`, `redirect_to oauth_authorization_path(authorization_params)`, return `nil`. If the user lacks `api_v3_enabled?`, same redirect with `flash[:error] = "This account can’t connect apps yet."`. Otherwise `sign_in user` and return the user.

- [ ] **Step 5: Wire the hooks** in `config/initializers/doorkeeper.rb`: `base_controller "Oauth::BaseController"`; `resource_owner_authenticator { oauth_resource_owner }`; delete the whole `Rails.application.config.to_prepare` block. Update the comment above `base_controller`.

- [ ] **Step 6: Make `new.html.erb` work signed out.** When `current_user` is nil, one form posting to `oauth_authorization_path` with the hidden fields, `email` (value `flash[:email]`), `password`, the flash partial, and a `Sign in and authorize` button; when signed in, the button reads `Authorize`. Cancel stays the `DELETE` form. Copy and styling are Task 3.

- [ ] **Step 7: Run the file, then the suite.** Expected: all pass. Update the assertion `"Allow My Reader to use your Feedbin account?"` in the PKCE test only when Task 3 changes the heading.

- [ ] **Step 8: Commit.** `git commit -m "OAuth authorize page signs in and authorizes in one step, without a trip to the login form"`

---

### Task 2: "Not you?"

**Files:**
- Create: `app/controllers/oauth/sessions_controller.rb`
- Modify: `config/routes.rb` (beside `use_doorkeeper`)
- Modify: `app/views/doorkeeper/authorizations/new.html.erb`
- Test: `test/integration/oauth_authorization_test.rb`

**Interfaces:**
- Consumes: `Oauth::BaseController#authorization_params`.
- Produces: `DELETE /oauth/session` → `Oauth::SessionsController#destroy`, route helper `oauth_session_path`. Route: `resource :session, only: :destroy, module: :oauth, path: "oauth/session", as: :oauth_session`.

- [ ] **Step 1: Write the failing tests.**

```ruby
test "not you signs out and returns to the authorize page" do
  sign_in_as @user

  delete oauth_session_path, params: authorize_params

  assert_redirected_to oauth_authorization_path(authorize_params)
  follow_redirect!
  assert_select "input[name=password]"
end

test "not you never redirects off site" do
  sign_in_as @user

  delete oauth_session_path, params: authorize_params.merge(redirect_uri: "https://evil.example/cb")

  assert_equal "www.example.com", URI(response.location).host
  follow_redirect!
  assert_includes response.body, "This app can’t connect to Feedbin"
end
```

- [ ] **Step 2: Run to verify they fail** (no route).
- [ ] **Step 3: Implement.** `Oauth::SessionsController < Oauth::BaseController`; `destroy` calls `sign_out` and `redirect_to oauth_authorization_path(authorization_params)`. In the signed-in variant of `new.html.erb` add a `button_to "Not you?"` to `oauth_session_path`, `method: :delete`, carrying the hidden fields, styled as a link.
- [ ] **Step 4: Run the file.** Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "OAuth authorize page lets a signed-in visitor switch accounts"`

---

### Task 3: Consent copy and mobile layout

**Files:**
- Create: `app/views/layouts/oauth_page.html.erb`
- Modify: `app/views/doorkeeper/authorizations/new.html.erb`, `error.html.erb`
- Test: `test/integration/oauth_authorization_test.rb`

**Interfaces:**
- Consumes: the form fields and flash keys from Task 1, `oauth_session_path` from Task 2.

- [ ] **Step 1: Reproduce the focus problem first.** Open `https://feedbin.resolv.app/oauth/authorize?...` (a valid authorize URL; build one from a `Doorkeeper::Application` in the dev database) in the iOS simulator using the device tools, focus each field of the current page and of `/login`, and record what happens. Then find the cause; suspects, in order: the vertically centred `min-h-full` wrapper in `layouts/form_page`, a fixed-height or `overflow: hidden` `html`/`body`, and the `visual-viewport` controller on `<body>`. Write the confirmed cause into the commit message. If the cause is none of these, report before continuing.

- [ ] **Step 2: Write the failing test** for the copy:

```ruby
test "the authorize page says what is granted, to whom, and how to undo it" do
  sign_in_as @user

  get oauth_authorization_path(authorize_params)

  assert_select "h1", text: "Authorize My Reader to use your Feedbin account"
  assert_includes response.body, "read and change your subscriptions, articles and settings"
  assert_includes response.body, @user.email
  assert_includes response.body, "returned to My Reader"
  assert_includes response.body, "revoke access any time in Settings"
end
```

Update the PKCE test's heading assertion to match.

- [ ] **Step 3: Build `layouts/oauth_page.html.erb`,** modelled on `layouts/form_page.html.erb` with these differences: content top-aligned (no `items-center` vertical centring); the document scrolls (no fixed-height inner scroller); padding uses `env(safe-area-inset-*)`; the logo is not a link away from the flow. Renders `layouts/application` like `form_page` does. Point `new.html.erb` and `error.html.erb` at it.

- [ ] **Step 4: Finish `new.html.erb`.**
  - Heading: `Authorize {App} to use your Feedbin account`.
  - Body: `{App} will be able to read and change your subscriptions, articles and settings.`
  - Signed in: `Signed in as {email}.` and the "Not you?" control.
  - `You’ll be returned to {App}.` For `http`/`https` redirect URIs append the host in parentheses.
  - `You can revoke access any time in Settings > API.`
  - Email: `type=email`, `autocomplete="username"`, `autocapitalize="off"`, `autocorrect="off"`, `spellcheck="false"`, `enterkeyhint="next"`. Password: `autocomplete="current-password"`, `enterkeyhint="go"`. No `autofocus`. Inputs render at 16px or larger. Reuse `Form::TextInputComponent`.
  - A `Forgot your password?` link as on `/login`.
  - Buttons full width and stacked below `sm`, primary first, each at least 44px tall; Cancel uses `button-secondary`.

- [ ] **Step 5: Run the file and the suite.** Expected: pass.

- [ ] **Step 6: Verify in the iOS simulator** (device tools; after boot, `simslim verify <udid> || simslim on <udid> --no-reboot`). Signed out and signed in, light and dark: focusing email then password keeps the focused field and the primary button's field visible above the keyboard; no zoom on focus; return key moves email → password → submits; password autofill offers; a wrong password comes back with the email filled and the error visible without scrolling. Take a screenshot of each state for the handoff.

- [ ] **Step 7: Commit.** `git commit -m "OAuth authorize page says what is granted and stays usable with the keyboard up"` with the confirmed cause from Step 1 in the body.
