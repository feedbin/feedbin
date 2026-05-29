# Stripe Modernization — Design

**Date:** 2026-05-29
**Status:** Approved for planning

## Goal

Replace Feedbin's legacy Stripe integration (gem `5.55.0`, API version pinned to `2016-07-06`, card tokens + `customer.source` + Card Element + Payment Request Button) with the modern stack:

- Stripe gem `5.55.0 → 19.2.0`
- Pinned API version `2016-07-06 → 2026-05-27.dahlia` (the `CURRENT` constant in gem 19.2.0)
- **Payment Element** with the **deferred PaymentIntent / SetupIntent** flow (collect payment details before creating the intent)
- JavaScript moved from `payments.js.coffee.erb` to a Stimulus controller
- Billing views converted to Phlex components
- Wallets (Apple Pay / Google Pay) folded into the Payment Element; the separate wallet-selector UI is removed
- Signup (`users#new`) stays card-less (email/password → trial)

### Decisions on record

- **Scope:** Full modernization — the API-version bump touches all affected billing code (services, `User` billing callbacks, webhook/`BillingEvent` processing, payment-history parsing, jobs), not just card collection.
- **Subscription lifecycle:** The Stripe Subscription is still created **at signup** (`create_customer` keeps creating a trialing subscription). The subscribe step therefore operates on that **existing** subscription — it never creates a second one.
- **Server architecture:** New `Billing::` service layer (the existing `Customer` PORO is replaced, not patched).
- **Tests:** Official `stripe-mock` server replaces the `feedbin/stripe-ruby-mock` fork.
- **API version:** Latest — `2026-05-27.dahlia`.
- **Payment Intents vs. Checkout Sessions:** Stripe's current docs steer new integrations toward the Checkout Sessions API with Payment Element. We use **Payment Intents + the deferred flow** per the explicit request. Recorded here as a knowing trade-off.

## Architecture

### Two collection flows, both deferred

**1. Subscribe** (trial → paid, free → paid, or plan change), in `settings/billing`. Operates on the subscription created at signup; the server-side path branches on whether the trial is still in the future:

- **Future trial → SetupIntent.** Client renders Payment Element with `mode: 'setup'`. On submit: `elements.submit()` → `stripe.createConfirmationToken({ elements })` → POST token + `plan_id`. Server confirms a SetupIntent with the token, sets the resulting PaymentMethod as the customer's default, and changes the existing subscription's price (keeping the future trial). No charge now; the first charge happens off-session when the trial ends.
- **Expired / immediate → PaymentIntent.** Client renders Payment Element with `mode: 'payment'`, `amount`, `currency`. On submit: same confirmation-token POST. Server updates the existing subscription (`items: [{ id:, price: }]`, `trial_end: 'now'`, `payment_behavior: 'default_incomplete'`), then confirms `latest_invoice`'s PaymentIntent with the token (this attaches the PM and charges on-session), and sets it as default.
- Server returns JSON. If `next_action` is required (3DS), it returns the `client_secret`; the Stimulus controller calls `stripe.handleNextAction`, then navigates.

**2. Update card** (existing subscriber), in `settings/billing/edit`:

- Client renders Payment Element with `mode: 'setup'`.
- On submit: confirmation token → server creates + confirms a **SetupIntent**, then sets the resulting PaymentMethod as `customer.invoice_settings.default_payment_method`.
- Same JSON + `handleNextAction` pattern.

Both endpoints return **JSON** (a change from today's form-submit + hidden `stripe_token` + redirect). The Stimulus controller orchestrates submit → confirmation token → fetch → optional next action → navigate.

### Server — `Billing::` service layer

Replaces the `Customer` PORO (`app/models/customer.rb`). Small, single-purpose objects:

- **`Billing::Customer`** — create / retrieve / update email / cancel. `customer.subscriptions` is no longer embedded → use `Stripe::Subscription.list(customer:)`.
- **`Billing::Subscription`** — `create_trialing` (signup); `change_price` via `Stripe::Subscription.update(id, items: [{ id: item_id, price: price_id }], proration_behavior:, trial_end:)` (replaces `subscription.plan=`); `subscribe` (the two-path SetupIntent/PaymentIntent flow above, operating on the existing subscription); `reopen_account` reworked off `invoice.status` (`open`/`draft`/`uncollectible`) + `Stripe::Invoice.pay` (the old `invoice.closed` / `attempt_count` fields are gone).
- **`Billing::PaymentMethod`** — confirm SetupIntent, set default PM, and the card brand/last4 lookup `payment_details` needs (`customer.sources.first` → `Stripe::PaymentMethod.list(customer:, type: 'card')` or the default PM).

### Controller endpoints

In `Settings::BillingsController` (routes under the existing `resource :billing`):

- `POST create_subscription` — confirmation token + `plan_id` → `Billing::Subscription.subscribe` (SetupIntent or PaymentIntent path) → JSON `{ status, client_secret?, requires_action? }`. (Name kept for the route; it activates the existing subscription rather than creating one.)
- `POST update_credit_card` — reworked to receive a confirmation token, confirm a SetupIntent via `Billing::PaymentMethod`, set default PM → JSON.
- `POST update_plan` — keeps its route; uses `Billing::Subscription` for the plan change.
- `GET payment_details` — uses `Billing::PaymentMethod`; cache key `payment_details:<id>:vN` bumped.

### Client — Stimulus

New `app/javascript/controllers/billing_controller.js`:

- **values:** publishable key, plan amounts + currency, mode (`subscription` | `setup`), endpoint URL, return URL, default plan id.
- **targets:** Payment Element mount, submit button, error region, plan radios.
- Loads Stripe.js, creates Elements with `mode`/`amount`/`currency`, updates `amount` on plan change, runs the submit → confirmation-token → fetch → `handleNextAction` → navigate sequence.
- Per-theme color logic in the CoffeeScript is replaced by the **Appearance API** (map Feedbin themes — `sunset`/`dusk`/`midnight`/dark/default — to appearance variables).
- Deleted: `app/assets/javascripts/payments/payments.js.coffee.erb` and all Payment Request Button code.

### Views — Phlex components

Convert all billing views; remove the wallet-selector radios and the country `<select>` (Payment Element collects payment method + billing details natively):

- `Billing::PaymentElementComponent` — shared element mount + Stripe.js include + stimulus wiring.
- `Billing::SubscribeFormComponent` — replaces `shared/billing/_billing_subscribe` + `shared/_credit_card_form`.
- `Billing::UpdateCardComponent` — replaces `settings/billings/edit.html.erb`.
- `Billing::StatusComponent` — replaces `shared/billing/_billing_status` and the `plan_free` / `plan_timed` / `plan_app` / `plan_default` partials.
- Convert `settings/billings/index.html.erb`.

Follows existing conventions: `ApplicationComponent`, the `stimulus` / `stimulus_item` helpers, and `Settings::ControlGroupComponent` / `ControlRowComponent` for plan-selector rows.

### Webhooks / BillingEvent / payment history (highest-risk surface)

Pinning a recent API version changes event/object shapes. These all need field-by-field verification under `2026-05-27.dahlia`:

- `BillingEvent#process_event` event types: `charge.succeeded`, `invoice.payment_failed`, `invoice.upcoming` (`amount_remaining`), `customer.subscription.updated` (`status` unpaid/active), `invoice.created`.
- `BillingEvent#invoice` / `#invoice_items` retrieval (`Stripe::Invoice.retrieve(...).lines.list`).
- `Settings::BillingsController#payments` history parser: `lines.data[].type == "subscription"` and `period.end` — line-item `type` and the invoice→subscription linkage moved in recent versions; rework accordingly.
- `UpdateStatementDescriptor` job: `Stripe::Invoice.update(id, statement_descriptor:)`.
- `cancel_billing` / `CancelBilling` job: `Stripe::Customer.delete(id)` (still valid).
- `StripeEvent` stays (gem supports stripe `< 20`); webhook signature handling unchanged.
- Regenerate webhook fixtures for the pinned API version.

### Configuration

`config/initializers/stripe.rb`: `Stripe.api_version = "2026-05-27.dahlia"`. `STRIPE_PUBLIC_KEY` continues to feed the client (via the component, not an ERB-interpolated asset).

## Testing

- Remove `stripe-ruby-mock` (the `feedbin` fork) from the Gemfile.
- Run the official **`stripe-mock`** server in dev/CI; point `Stripe.api_base` (and uploads base) at it in the test env with a test key.
- Rewrite `test/test_helper.rb#create_stripe_plan` → Price creation, and `test/support/factory_helper.rb#stripe_user`.
- Replace `StripeMock.mock_webhook_event` usages with static JSON fixtures in `test/fixtures/stripe_webhooks/` for the pinned API version.
- Affected tests: `billing_event_test`, `settings/billings_controller_test`, `users_controller_test`, `api/v2/users_controller_test`, `cancel_billing_test`, `update_statement_descriptor_test`, `trial_expiration_test`, `user_deleter_test`.
- **Risk to verify first:** stripe-mock may not support server-side *confirm-with-ConfirmationToken*. If not, stub those specific calls with WebMock; keep the stub surface minimal and documented.

## Phasing (for the implementation plan)

1. Gem upgrade + pinned API version + `stripe-mock` harness; adapt existing tests to green.
2. Server `Billing::` services + JSON intent endpoints.
3. Stimulus controller + Payment Element + Appearance API.
4. Phlex components; delete wallet/country UI + CoffeeScript.
5. Webhook / `BillingEvent` / payment-history field migration + fixture regeneration.

## Out of scope

- Signup card collection (`users#new` stays email/password → trial).
- In-app purchase / App Store subscription handling (`in_app_purchase`, `app_store_notification_processor`) — only where it intersects payment-history display.
- Migrating to the Checkout Sessions API (knowing trade-off; Payment Intents chosen).

## Open items to confirm during implementation

- Exact invoice / line-item field shapes under `2026-05-27.dahlia` (invoice→subscription linkage, line-item `type`).
- That legacy plan ids (e.g. `basic-yearly-3`) resolve as valid **Price** ids in the live Stripe account.
- stripe-mock coverage of the deferred confirm path (else WebMock stubs).

## Files touched (inventory)

**Config/deps:** `Gemfile`, `Gemfile.lock`, `config/initializers/stripe.rb`, `config/routes.rb`, test env config.

**Server:** new `app/models/billing/customer.rb`, `billing/subscription.rb`, `billing/payment_method.rb` (replacing `app/models/customer.rb`); `app/models/user.rb` (`create_customer`, `update_billing`, `cancel_billing`, `stripe_customer`); `app/controllers/settings/billings_controller.rb`; `app/models/billing_event.rb`; `app/jobs/update_statement_descriptor.rb`, `cancel_billing.rb`.

**Client:** new `app/javascript/controllers/billing_controller.js`; delete `app/assets/javascripts/payments/payments.js.coffee.erb`.

**Views → Phlex:** new components under `app/views/components/billing/`; remove `app/views/shared/_credit_card_form.html.erb`, `app/views/shared/billing/_billing_subscribe.html.erb`, `_billing_status.html.erb` and `plan_*` partials; convert `app/views/settings/billings/index.html.erb` and `edit.html.erb`.

**Tests:** `test/test_helper.rb`, `test/support/factory_helper.rb`, billing-related tests listed above, `test/fixtures/stripe_webhooks/`.
