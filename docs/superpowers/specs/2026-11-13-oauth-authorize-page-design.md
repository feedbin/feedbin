# OAuth authorize page

## Intent

People reach `/oauth/authorize` from a native app's in-app browser, on a phone, usually signed out. Today they are bounced to the normal `/login` with a "Please sign in." notice, sign in, then land on a second Allow / Deny screen. It should be one purpose-built screen with one button, that says clearly what is being granted and works well with the keyboard up.

## Goals

- `/oauth/authorize` renders its own page whether or not the visitor is signed in. No redirect to `/login`, no flash notice.
- One step. Signed out: email, password, **Sign in and authorize**. Signed in: **Authorize**.
- Consent copy that follows common practice (below).
- Comfortable on a phone inside an in-app browser: focused fields scroll into view above the keyboard, no zoom on focus, autofill works.

## Non-goals

- Sign-up from this page. A "Forgot your password?" link is enough.
- Changing scopes, token issuance, PKCE, or the token endpoint.
- Restyling the normal `/login` page.

## Anti-goals

- Issuing a grant without a visible, deliberate button press.
- Weakening Doorkeeper's client / redirect URI validation. An invalid client or redirect URI still renders the error page and never redirects.
- Any state where a failed sign-in loses the OAuth parameters.

## Approaches

1. **Stock Doorkeeper controller, config hooks only (chosen).** Three hooks cover everything:
   - `base_controller "Oauth::BaseController"`: a small controller inheriting `ApplicationController` that skips the `authorize` filter (the source of the redirect and the "Please sign in." notice), sets `layout false`, and holds `assign_v3_scopes`. Only Doorkeeper's authorizations controller inherits it, since the others are skipped in routes and the token endpoint uses the metal base.
   - `resource_owner_authenticator`: returns `current_user` when signed in; on a signed-out POST checks email and password, calls `sign_in`, and returns the user; otherwise returns nil so the page renders signed out. The logic lives in a method on `Oauth::BaseController`; the block only calls it.
   - Our own `doorkeeper/authorizations/new` view, with signed-in and signed-out variants.

   The `class_eval` block in `config/initializers/doorkeeper.rb` is deleted. No Doorkeeper private methods are called.
2. **Subclass Doorkeeper's controller.** Works, but reaches into private methods (`pre_auth`, `authorize_response`, `redirect_or_render`) for something the hooks already allow.
3. **Keep patching in the initializer.** Grows a monkeypatch that the base controller makes unnecessary.
4. **A separate `/oauth/login` page that redirects back and auto-approves.** Still a redirect hop, and consent has to be carried between pages.

Chosen: 1. Doorkeeper's controller stays untouched and keeps doing all protocol validation, code issuing, redirect and deny.

To confirm first when building: that Doorkeeper renders `new` (and handles `destroy`) when the authenticator returns nil. This is read from its source, not yet run. If it does not hold, come back before falling back to approach 2.

## Behaviour

**GET `/oauth/authorize`**

- Invalid client, redirect URI or request: existing error page, as today.
- Signed out: page with consent copy, email, password, **Sign in and authorize**, Cancel.
- Signed in with API v3 enabled: same page without fields. "Signed in as you@example.com", **Authorize**, Cancel, and a "Not you?" link.
- Signed in without API v3: 404, as today.

**POST `/oauth/authorize`**

- Signed out: look up the user and check the password.
  - Wrong: redirect back to the same authorize URL (all OAuth parameters in the query string) with "Invalid email or password" and the email kept. A redirect rather than an in-place re-render, because re-rendering would need Doorkeeper's private `pre_auth`.
  - Right but API v3 not enabled: do not sign in; redirect back the same way with an error saying this account can't connect apps yet. *(My call.)*
  - Right: `sign_in user` (normal Feedbin session cookie, as decided), then issue the grant and redirect to the app.
- Signed in: issue the grant and redirect, as today.

**Cancel** sends `DELETE /oauth/authorize`, which returns `access_denied` to the app's redirect URI. It works signed out.

**"Not you?"** signs out and returns to the same authorize URL with the same parameters, showing the signed-out variant.

Note: signed-out visitors with a valid `client_id` can now see this page, where before everything sat behind sign-in plus the API v3 flag. The page reveals only the app's name.

## Consent copy

- Heading names the app: "Authorize {App} to use your Feedbin account".
- What it can do, plainly: read and change your subscriptions, articles and settings.
- Who: the signed-in email, or the fields.
- Where it goes next: "You'll be returned to {App}" (show the redirect host for http(s) redirect URIs; for custom schemes the app name is enough).
- How to undo it: "You can revoke access any time in Settings > API."
- Primary button states the action ("Sign in and authorize" / "Authorize"); Cancel is visually secondary.
- No pre-ticked options, no marketing, no sign-up prompt.

## Mobile

- Own layout rather than `layouts/form_page`: content top-aligned, not vertically centred, so the form does not jump or get covered when the keyboard opens.
- The document itself scrolls (no fixed-height inner scroller), so iOS scrolls the focused field into view. The cause of today's focus problem is to be reproduced first in the iOS simulator, then fixed; this is the suspected cause, not a confirmed one.
- Inputs at 16px or larger to stop focus zoom. Email: `type=email`, `autocomplete=username`, `autocapitalize=off`, `autocorrect=off`. Password: `autocomplete=current-password`. `enterkeyhint` set so the keyboard's return key moves to password, then submits.
- No autofocus, so the consent text is readable before the keyboard appears. *(My call.)*
- Safe-area padding; tap targets at least 44px; buttons stacked full width on narrow screens with the primary first.
- Light and dark themes, as the existing form pages.

## Left to the builder

- How "Not you?" is routed (follow `rails-conventions`).
- Exact markup and classes, reusing `Form::TextInputComponent` and existing button styles where they fit.
- Tests: controller tests for each row under Behaviour, including that parameters survive a failed sign-in and that an invalid redirect URI never redirects. Update `test/controllers/oauth_authorization_test.rb` if present under another path.
- Verify in the iOS simulator with the keyboard up, light and dark.
