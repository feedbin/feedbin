# Stripe Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Feedbin's legacy 2016 Stripe integration with gem 19.2.0, API version `2026-05-27.dahlia`, the Payment Element + deferred PaymentIntent/SetupIntent flow, a Stimulus controller, Phlex components, and a `stripe-mock`-based test harness.

**Architecture:** A `Billing::` service layer (`Billing::Customer`, `Billing::Subscription`, `Billing::PaymentMethod`) wraps the modern API and replaces the old `Customer` PORO. Two deferred collection flows — subscribe (`mode: 'subscription'`) and update-card (`mode: 'setup'`) — render the Payment Element, create a confirmation token client-side, and confirm intents server-side via JSON endpoints. Webhook/`BillingEvent` processing and payment-history parsing are migrated to the new API shapes.

**Tech Stack:** Rails (Minitest, ActionController::TestCase), Stripe Ruby gem 19.2.0, `stripe_event`, Stripe.js Payment Element, Hotwired Stimulus, Phlex components, `stripe-mock` (official Go mock server) for tests.

**Spec:** `docs/superpowers/specs/2026-05-29-stripe-modernization-design.md`

**Conventions for every task:**
- Prepend `source ~/.bash_profile` to all shell commands (PATH + Ruby env).
- Targeted test run: `bundle exec rails test <file> -n <test_name>`. Full suite: `bundle exec rake`.
- Commit after each green task with the message shown in the task's commit step.

---

## Phase 0 — Discovery & Harness

### Task 0.1: Pin the gem and API version

**Files:**
- Modify: `Gemfile`
- Modify: `config/initializers/stripe.rb:1-2`

- [ ] **Step 1: Bump the gem and drop the mock fork**

In `Gemfile`, change the stripe line and remove the `stripe-ruby-mock` line:

```ruby
gem "stripe", "~> 19.2.0"
gem "stripe_event"
```

Delete this line entirely (it lives in the test/development group):

```ruby
gem "stripe-ruby-mock", github: "feedbin/stripe-ruby-mock", branch: "feedbin", require: "stripe_mock"
```

- [ ] **Step 2: Install**

Run: `source ~/.bash_profile && bundle install`
Expected: resolves `stripe (19.2.0)`; `stripe-ruby-mock` no longer in `Gemfile.lock`. If `stripe_event` blocks resolution, run `bundle update stripe stripe_event` (stripe_event 2.x allows `stripe < 20`).

- [ ] **Step 3: Pin the API version**

In `config/initializers/stripe.rb`, set:

```ruby
Stripe.api_version = "2026-05-27.dahlia"
```

(Leave the `StripeEvent.signing_secret`, `STRIPE_PUBLIC_KEY`, and `StripeEvent.setup` block unchanged.)

- [ ] **Step 4: Verify the gem loads at the pinned version**

Run: `source ~/.bash_profile && bundle exec ruby -e 'require "stripe"; puts Stripe::VERSION; puts Stripe.api_version'`
Expected: `19.2.0` then `2026-05-27.dahlia`.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/stripe.rb
git commit -m "Upgrade stripe gem to 19.2.0 and pin API version 2026-05-27.dahlia"
```

---

### Task 0.2: Stand up stripe-mock in the test environment

**Files:**
- Create: `test/support/stripe_mock_server.rb`
- Modify: `test/test_helper.rb:41` (the `StripeMock.webhook_fixture_path` line and the `require`s)
- Modify: `.github/workflows/*` CI (add stripe-mock service) — adjust to the actual CI file present.

- [ ] **Step 1: Install stripe-mock locally for dev**

Run: `source ~/.bash_profile && brew install stripe/stripe-mock/stripe-mock && stripe-mock --version`
Expected: prints a version. (CI installs it via a service container / release download — see Step 5.)

- [ ] **Step 2: Write a helper that points the gem at stripe-mock**

Create `test/support/stripe_mock_server.rb`:

```ruby
# Points the Stripe gem at a locally-running stripe-mock instance for the test suite.
# Start stripe-mock before running tests:  stripe-mock -http-port 12111
module StripeMockServer
  HOST = ENV.fetch("STRIPE_MOCK_HOST", "http://localhost:12111")

  def self.configure!
    Stripe.api_key = "sk_test_123"
    Stripe.api_base = HOST
    Stripe.connect_base = HOST
    Stripe.uploads_base = HOST
  end
end
```

- [ ] **Step 3: Wire it into test_helper and remove stripe-ruby-mock references**

In `test/test_helper.rb`, remove the line `StripeMock.webhook_fixture_path = "./test/fixtures/stripe_webhooks/"` and add the require alongside the other `require "support/..."` lines:

```ruby
require "support/stripe_mock_server"
```

After the `require File.expand_path("../../config/environment", __FILE__)` line and the other setup, add:

```ruby
StripeMockServer.configure!
```

- [ ] **Step 4: Verify the gem talks to stripe-mock**

Start the server in one terminal: `source ~/.bash_profile && stripe-mock -http-port 12111`
In another: `source ~/.bash_profile && STRIPE_MOCK_HOST=http://localhost:12111 bundle exec ruby -e 'require "./config/environment"; require "./test/support/stripe_mock_server"; StripeMockServer.configure!; puts Stripe::Customer.create(email: "a@b.com").id'`
Expected: prints a `cus_...` id with no network error.

- [ ] **Step 5: Add stripe-mock to CI**

In the CI workflow that runs `bundle exec rake`, add a service container before the test step:

```yaml
    services:
      stripe-mock:
        image: stripe/stripe-mock:latest
        ports:
          - 12111:12111
```

Set `STRIPE_MOCK_HOST: http://localhost:12111` in the job `env`. (Match the existing workflow's structure; if Feedbin runs tests outside containers, download the stripe-mock release binary in a setup step instead.)

- [ ] **Step 6: Commit**

```bash
git add test/support/stripe_mock_server.rb test/test_helper.rb .github
git commit -m "Replace stripe-ruby-mock with stripe-mock test harness"
```

---

### Task 0.3: Discovery — capture real object shapes under the new API version

This task produces a short reference doc of the exact field names later tasks depend on. It is executable verification, not a placeholder.

**Files:**
- Create: `docs/superpowers/notes/stripe-api-shapes.md`

- [ ] **Step 1: Capture invoice, subscription, and line-item shapes from stripe-mock**

With stripe-mock running, run:

```bash
source ~/.bash_profile && STRIPE_MOCK_HOST=http://localhost:12111 bundle exec ruby -e '
require "./config/environment"; require "./test/support/stripe_mock_server"; StripeMockServer.configure!
cust = Stripe::Customer.create(email: "a@b.com")
price = Stripe::Price.create(unit_amount: 5000, currency: "usd", recurring: {interval: "year"}, product_data: {name: "Yearly"})
sub  = Stripe::Subscription.create(customer: cust.id, items: [{price: price.id}], payment_behavior: "default_incomplete", expand: ["latest_invoice.payment_intent", "pending_setup_intent"])
puts "SUBSCRIPTION KEYS: #{sub.keys.sort}"
puts "ITEM KEYS: #{sub.items.data.first.keys.sort}"
inv = sub.latest_invoice
puts "INVOICE KEYS: #{inv.keys.sort}" if inv
puts "INVOICE LINE KEYS: #{inv.lines.data.first.keys.sort}" if inv && inv.lines.data.first
'
```

- [ ] **Step 2: Record findings**

Create `docs/superpowers/notes/stripe-api-shapes.md` and record, from the output above and the live Stripe API reference for `2026-05-27.dahlia`, the answers to:
- How is an invoice linked to its subscription? (`invoice.subscription` vs `invoice.parent.subscription_details.subscription`.)
- Does an invoice line item still expose `type == "subscription"`, and where does its billing `period` live?
- On a trialing `default_incomplete` subscription, is the intent under `pending_setup_intent` (SetupIntent) and is `latest_invoice.payment_intent` null?
- Does `Stripe::Invoice` still accept `statement_descriptor` on update?

Write each as a one-line confirmed fact. **Phase 4 (webhooks/history) depends on these answers.**

- [ ] **Step 3: Confirm legacy plan ids resolve as Price ids**

Against the **live test-mode** account (not stripe-mock), run:

```bash
source ~/.bash_profile && STRIPE_API_KEY=$STRIPE_API_KEY bundle exec ruby -e '
require "stripe"; Stripe.api_key = ENV["STRIPE_API_KEY"]; Stripe.api_version = "2026-05-27.dahlia"
%w[basic-monthly basic-yearly basic-monthly-2 basic-yearly-2 basic-monthly-3 basic-yearly-3].each do |id|
  begin; p = Stripe::Price.retrieve(id); puts "#{id} => OK unit_amount=#{p.unit_amount}"; rescue => e; puts "#{id} => MISSING (#{e.class})"; end
end'
```

Record results in the notes file. If any are `MISSING`, the implementation must create Price objects for them; note that explicitly.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/stripe-api-shapes.md
git commit -m "Document Stripe object shapes under 2026-05-27.dahlia"
```

---

## Phase 1 — `Billing::` service layer

### Task 1.1: `Billing::Customer`

**Files:**
- Create: `app/models/billing/customer.rb`
- Test: `test/models/billing/customer_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/billing/customer_test.rb`:

```ruby
require "test_helper"

class Billing::CustomerTest < ActiveSupport::TestCase
  test "create makes a Stripe customer and returns a wrapper" do
    customer = Billing::Customer.create(email: "new@example.com")
    assert_match(/\Acus_/, customer.id)
    assert_equal "new@example.com", customer.email
  end

  test "retrieve loads an existing customer" do
    created = Stripe::Customer.create(email: "x@example.com")
    customer = Billing::Customer.retrieve(created.id)
    assert_equal created.id, customer.id
  end

  test "update_email changes the email" do
    customer = Billing::Customer.create(email: "old@example.com")
    customer.update_email("changed@example.com")
    assert_equal "changed@example.com", Stripe::Customer.retrieve(customer.id).email
  end

  test "subscription returns the customer's first subscription or nil" do
    customer = Billing::Customer.create(email: "s@example.com")
    assert_nil customer.subscription
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/customer_test.rb`
Expected: FAIL — `uninitialized constant Billing::Customer` (ensure stripe-mock is running).

- [ ] **Step 3: Implement**

Create `app/models/billing/customer.rb`:

```ruby
module Billing
  # Wraps a Stripe::Customer using the modern API. Subscriptions are no longer
  # embedded on the customer object, so they are fetched on demand.
  class Customer
    attr_reader :customer
    delegate :id, :email, to: :customer

    def self.create(email:)
      new(Stripe::Customer.create(email: email))
    end

    def self.retrieve(customer_id)
      new(Stripe::Customer.retrieve(customer_id))
    end

    def initialize(customer)
      @customer = customer
    end

    def update_email(email)
      @customer = Stripe::Customer.update(id, email: email)
    end

    def subscription
      @subscription ||= Stripe::Subscription.list(customer: id, limit: 1, status: "all").data.first
    end

    def unpaid?
      subscription&.status == "unpaid"
    end

    def cancel
      Stripe::Customer.delete(id)
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/customer_test.rb`
Expected: PASS (4 runs, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/models/billing/customer.rb test/models/billing/customer_test.rb
git commit -m "Add Billing::Customer service"
```

---

### Task 1.2: `Billing::Subscription` — create with trial and plan change

**Files:**
- Create: `app/models/billing/subscription.rb`
- Test: `test/models/billing/subscription_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/billing/subscription_test.rb`:

```ruby
require "test_helper"

class Billing::SubscriptionTest < ActiveSupport::TestCase
  setup do
    @customer = Stripe::Customer.create(email: "sub@example.com")
    @price = Stripe::Price.create(
      unit_amount: 5000, currency: "usd",
      recurring: {interval: "year"}, product_data: {name: "Yearly"}
    )
  end

  test "create_trialing makes an incomplete trialing subscription with no immediate charge" do
    sub = Billing::Subscription.create_trialing(
      customer_id: @customer.id, price_id: @price.id, trial_end: 30.days.from_now
    )
    assert_match(/\Asub_/, sub.id)
  end

  test "change_price updates the subscription item price" do
    stripe_sub = Stripe::Subscription.create(
      customer: @customer.id, items: [{price: @price.id}], payment_behavior: "default_incomplete"
    )
    new_price = Stripe::Price.create(
      unit_amount: 7000, currency: "usd",
      recurring: {interval: "year"}, product_data: {name: "Yearly 2"}
    )
    Billing::Subscription.change_price(
      subscription_id: stripe_sub.id, price_id: new_price.id, trial_end: nil
    )
    reloaded = Stripe::Subscription.retrieve(stripe_sub.id)
    assert_equal new_price.id, reloaded.items.data.first.price.id
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/subscription_test.rb`
Expected: FAIL — `uninitialized constant Billing::Subscription`.

- [ ] **Step 3: Implement**

Create `app/models/billing/subscription.rb`:

```ruby
module Billing
  # Modern subscription operations. Replaces Stripe::Subscription.create(plan:)
  # and subscription.plan= with the items/price API. The subscription itself is
  # created at signup (create_trialing); later operations mutate that existing
  # subscription rather than creating new ones.
  class Subscription
    # Used at signup: a trialing, payment-method-less subscription.
    def self.create_trialing(customer_id:, price_id:, trial_end:)
      Stripe::Subscription.create(
        customer: customer_id,
        items: [{price: price_id}],
        trial_end: trial_end.to_i,
        payment_behavior: "default_incomplete",
        trial_settings: {end_behavior: {missing_payment_method: "pause"}},
        expand: ["pending_setup_intent"]
      )
    end

    # Switch the existing subscription's price (used by update_plan / users#update
    # for customers who already have a payment method on file). Keeps a future
    # trial; ends it immediately if the trial has already passed.
    def self.change_price(subscription_id:, price_id:, trial_end:)
      sub = Stripe::Subscription.retrieve(subscription_id)
      params = {
        items: [{id: sub.items.data.first.id, price: price_id}],
        proration_behavior: "none"
      }
      params[:trial_end] = trial_end_param(trial_end) if trial_end
      Stripe::Subscription.update(subscription_id, params)
    end

    def self.trial_end_param(trial_end)
      return "now" if trial_end.nil? || trial_end.past?
      trial_end.to_i
    end
  end
end
```

(The `subscribe` two-path method is added in Task 1.5, after `Billing::PaymentMethod` exists, because it sets the default payment method.)

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/subscription_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/billing/subscription.rb test/models/billing/subscription_test.rb
git commit -m "Add Billing::Subscription service"
```

---

### Task 1.3: `Billing::Subscription#reopen_account`

**Files:**
- Modify: `app/models/billing/subscription.rb`
- Test: `test/models/billing/subscription_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/models/billing/subscription_test.rb`:

```ruby
  test "reopen pays an open invoice for an unpaid customer" do
    # stripe-mock returns a payable invoice; assert the call succeeds and returns truthy.
    stripe_sub = Stripe::Subscription.create(
      customer: @customer.id, items: [{price: @price.id}], payment_behavior: "default_incomplete"
    )
    assert_nothing_raised do
      Billing::Subscription.reopen_account(@customer.id)
    end
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/subscription_test.rb -n /reopen/`
Expected: FAIL — `undefined method 'reopen_account'`.

- [ ] **Step 3: Implement**

Add to `app/models/billing/subscription.rb` inside the class:

```ruby
    # Replaces the old invoice.closed / attempt_count logic. After a customer
    # updates a failed card, attempt to pay the latest open invoice; if the
    # subscription is unpaid, restart its billing cycle.
    def self.reopen_account(customer_id)
      invoice = Stripe::Invoice.list(customer: customer_id, limit: 1).data.first
      return unless invoice

      case invoice.status
      when "open", "uncollectible"
        Stripe::Invoice.pay(invoice.id)
      when "draft"
        subscription = Stripe::Subscription.list(customer: customer_id, status: "unpaid", limit: 1).data.first
        if subscription
          Stripe::Subscription.update(subscription.id, billing_cycle_anchor: "now", proration_behavior: "none")
        end
      end
    end
```

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/subscription_test.rb -n /reopen/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/billing/subscription.rb test/models/billing/subscription_test.rb
git commit -m "Add Billing::Subscription.reopen_account"
```

---

### Task 1.4: `Billing::PaymentMethod`

**Files:**
- Create: `app/models/billing/payment_method.rb`
- Test: `test/models/billing/payment_method_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/billing/payment_method_test.rb`:

```ruby
require "test_helper"

class Billing::PaymentMethodTest < ActiveSupport::TestCase
  setup do
    @customer = Stripe::Customer.create(email: "pm@example.com")
  end

  test "summary returns 'No payment info' when no card is attached" do
    assert_equal "No payment info", Billing::PaymentMethod.summary(@customer.id)
  end

  test "create_setup_intent returns a setup intent for the customer" do
    intent = Billing::PaymentMethod.create_setup_intent(@customer.id)
    assert_match(/\Aseti_/, intent.id)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/payment_method_test.rb`
Expected: FAIL — `uninitialized constant Billing::PaymentMethod`.

- [ ] **Step 3: Implement**

Create `app/models/billing/payment_method.rb`:

```ruby
module Billing
  # Card update via SetupIntent, default-PM management, and the card summary
  # shown on the billing page (replaces customer.sources.first).
  class PaymentMethod
    def self.create_setup_intent(customer_id)
      Stripe::SetupIntent.create(customer: customer_id, usage: "off_session")
    end

    # Confirm a SetupIntent with a client-collected ConfirmationToken, then make
    # the resulting payment method the customer's default for invoices.
    def self.confirm_and_set_default(customer_id:, confirmation_token:)
      intent = Stripe::SetupIntent.create(
        customer: customer_id, usage: "off_session",
        confirmation_token: confirmation_token, confirm: true
      )
      if intent.status == "succeeded"
        set_default(customer_id, intent.payment_method)
      end
      intent
    end

    def self.set_default(customer_id, payment_method_id)
      Stripe::Customer.update(customer_id, invoice_settings: {default_payment_method: payment_method_id})
    end

    # "Visa ××42" style summary, or "No payment info".
    def self.summary(customer_id)
      pm = default_card(customer_id)
      return "No payment info" unless pm
      "#{pm.card.brand.capitalize} ××#{pm.card.last4[-2..]}"
    end

    def self.default_card(customer_id)
      customer = Stripe::Customer.retrieve(customer_id)
      default_id = customer.invoice_settings&.default_payment_method
      if default_id
        Stripe::PaymentMethod.retrieve(default_id)
      else
        Stripe::PaymentMethod.list(customer: customer_id, type: "card", limit: 1).data.first
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/payment_method_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/billing/payment_method.rb test/models/billing/payment_method_test.rb
git commit -m "Add Billing::PaymentMethod service"
```

---

### Task 1.5: `Billing::Subscription.subscribe` (two-path activation)

**Files:**
- Modify: `app/models/billing/subscription.rb`
- Test: `test/models/billing/subscription_test.rb`

This is the subscribe-step entry point. It operates on the subscription created at signup. For a **future** trial it confirms a SetupIntent and keeps the trial; for an **expired/immediate** subscription it ends the trial now and confirms the first invoice's PaymentIntent on-session. Both attach the PaymentMethod and set it as the customer default.

- [ ] **Step 1: Write the failing test**

Add to `test/models/billing/subscription_test.rb`. Because confirming a ConfirmationToken is a live-only operation, drive the branch selection with stubs and assert the right Stripe calls happen:

```ruby
  test "subscribe uses the setup-intent path for a future trial" do
    stripe_sub = Stripe::Subscription.create(
      customer: @customer.id, items: [{price: @price.id}], payment_behavior: "default_incomplete"
    )

    setup_called = false
    Stripe::SetupIntent.stub(:create, OpenStruct.new(status: "succeeded", payment_method: "pm_1")) do
      Stripe::Customer.stub(:update, OpenStruct.new) do
        # change_price runs against stripe-mock for real
        intent = Billing::Subscription.subscribe(
          customer_id: @customer.id, subscription_id: stripe_sub.id,
          price_id: @price.id, confirmation_token: "ctoken_1",
          trial_end: 30.days.from_now
        )
        setup_called = (intent.status == "succeeded")
      end
    end
    assert setup_called
  end

  test "subscribe uses the payment-intent path for an expired trial" do
    stripe_sub = Stripe::Subscription.create(
      customer: @customer.id, items: [{price: @price.id}], payment_behavior: "default_incomplete"
    )

    pi = OpenStruct.new(status: "succeeded", payment_method: "pm_1")
    Stripe::PaymentIntent.stub(:confirm, pi) do
      Stripe::Customer.stub(:update, OpenStruct.new) do
        intent = Billing::Subscription.subscribe(
          customer_id: @customer.id, subscription_id: stripe_sub.id,
          price_id: @price.id, confirmation_token: "ctoken_1",
          trial_end: 1.day.ago
        )
        assert_equal "succeeded", intent.status
      end
    end
  end
```

(`require "ostruct"` at the top of the test file if not already present.)

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/subscription_test.rb -n /subscribe/`
Expected: FAIL — `undefined method 'subscribe'`.

- [ ] **Step 3: Implement**

Add to `app/models/billing/subscription.rb` inside the class:

```ruby
    # Subscribe step. Operates on the existing (signup-created) subscription.
    # Returns the confirmed SetupIntent or PaymentIntent.
    def self.subscribe(customer_id:, subscription_id:, price_id:, confirmation_token:, trial_end:)
      if trial_end && trial_end.future?
        intent = Stripe::SetupIntent.create(
          customer: customer_id, usage: "off_session",
          confirmation_token: confirmation_token, confirm: true
        )
        if intent.status == "succeeded"
          Billing::PaymentMethod.set_default(customer_id, intent.payment_method)
          change_price(subscription_id: subscription_id, price_id: price_id, trial_end: trial_end)
        end
        intent
      else
        sub = Stripe::Subscription.retrieve(subscription_id)
        Stripe::Subscription.update(subscription_id, {
          items: [{id: sub.items.data.first.id, price: price_id}],
          trial_end: "now",
          proration_behavior: "none",
          payment_behavior: "default_incomplete",
          expand: ["latest_invoice.confirmation_secret"]
        })
        invoice = Stripe::Invoice.retrieve({id: Stripe::Subscription.retrieve(subscription_id).latest_invoice, expand: ["confirmation_secret"]})
        payment_intent_id = invoice.confirmation_secret.client_secret.split("_secret_").first
        intent = Stripe::PaymentIntent.confirm(payment_intent_id, confirmation_token: confirmation_token)
        Billing::PaymentMethod.set_default(customer_id, intent.payment_method) if intent.status == "succeeded"
        intent
      end
    end
```

> **Note:** the `latest_invoice.confirmation_secret` → PaymentIntent-id extraction depends on the shape confirmed in Task 0.3. If the notes say the intent is exposed as `latest_invoice.payment_intent`, retrieve that id directly instead of parsing `confirmation_secret`. Adjust before running Step 4.

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing/subscription_test.rb -n /subscribe/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/billing/subscription.rb test/models/billing/subscription_test.rb
git commit -m "Add Billing::Subscription.subscribe two-path activation"
```

---

## Phase 2 — User model + controller endpoints

### Task 2.1: Migrate `User` billing callbacks to `Billing::`

**Files:**
- Modify: `app/models/user.rb` (`create_customer` ~321, `update_billing` ~331, `cancel_billing` ~358, `stripe_customer` ~354)
- Delete: `app/models/customer.rb`
- Test: `test/controllers/users_controller_test.rb` (existing), `test/jobs/cancel_billing_test.rb` (existing)

- [ ] **Step 1: Update the factory helper to the modern API (so existing tests can run)**

In `test/support/factory_helper.rb`, replace `stripe_user` and remove `create_stripe_plan` token usage. Replace the body with:

```ruby
  def stripe_user
    plan = plans(:trial)
    create_stripe_price(plan)
    User.create(email: "stripe-#{SecureRandom.hex(4)}@example.com", password: default_password, plan: plan)
  end
```

In `test/test_helper.rb`, replace `create_stripe_plan` with:

```ruby
  def create_stripe_price(plan)
    Stripe::Price.create(
      id: plan.stripe_id,
      unit_amount: plan.price_in_cents,
      currency: "usd",
      recurring: {interval: "day"},
      product_data: {name: plan.name}
    )
  rescue Stripe::InvalidRequestError
    Stripe::Price.retrieve(plan.stripe_id)
  end
```

- [ ] **Step 2: Implement the User changes**

In `app/models/user.rb`, replace `create_customer`:

```ruby
  def create_customer
    customer = Billing::Customer.create(email: email)
    self.customer_id = customer.id
    Billing::Subscription.create_trialing(
      customer_id: customer.id, price_id: plan.stripe_id, trial_end: trial_end
    )
    if coupon_code
      coupon_record = Coupon.find_by_coupon_code(coupon_code)
      coupon_record.update(redeemed: true)
      self.coupon = coupon_record
    end
  end
```

Replace `update_billing` (card updates now happen through the SetupIntent endpoint, so the `stripe_token` branch is removed). The `skip_billing_plan_change` flag lets the subscribe endpoint persist the plan column without firing a second price change (it already drove the Stripe side via `Billing::Subscription.subscribe`):

```ruby
  def update_billing
    stripe_customer.update_email(email) if email_changed?

    if plan_id_changed? && !skip_billing_plan_change && stripe_customer.subscription
      Billing::Subscription.change_price(
        subscription_id: stripe_customer.subscription.id,
        price_id: plan.stripe_id,
        trial_end: trial_end
      )
    end
  rescue Stripe::StripeError => exception
    ErrorService.notify(exception)
    errors.add :base, exception.message.to_s
    throw(:abort)
  end
```

Add `skip_billing_plan_change` to the `attr_accessor` list near the top of `app/models/user.rb:2` (alongside `:stripe_token`, `:coupon_code`, etc.):

```ruby
  attr_accessor :stripe_token, :old_password_valid, :update_auth_token,
    :password_reset, :coupon_code, :is_trialing, :coupon_valid, :deleted,
    :skip_billing_plan_change
```

Replace `stripe_customer` and `cancel_billing`:

```ruby
  def stripe_customer
    @stripe_customer ||= Billing::Customer.retrieve(customer_id)
  end

  def cancel_billing
    Billing::Customer.retrieve(customer_id).cancel
  rescue Stripe::StripeError => e
    logger.error "Stripe Error: " + e.message
    errors.add :base, "#{e.message}."
    CancelBilling.perform_async(customer_id)
  end
```

Remove the now-unused `attr_accessor :stripe_token` token from the billing flow only if nothing else references it (search first — see Step 3). Keep `:coupon_code` etc.

- [ ] **Step 3: Delete the old wrapper and check for stragglers**

Run: `source ~/.bash_profile && grep -rn "Customer\.\(create\|retrieve\)\|\.update_source\|\.update_plan\|customer\.sources\|\.stripe_token" app lib | grep -v "Billing::"`
Expected after edits: only references inside views you'll convert in Phase 3 and the controller (next task). Delete `app/models/customer.rb`:

```bash
git rm app/models/customer.rb
```

- [ ] **Step 4: Run the affected tests**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/users_controller_test.rb test/jobs/cancel_billing_test.rb`
Expected: PASS (update assertions in those tests if they reference `customer.sources`; the cancel test should still pass via `Stripe::Customer.delete`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Migrate User billing callbacks to Billing:: services"
```

---

### Task 2.2: `create_subscription` JSON endpoint

**Files:**
- Modify: `config/routes.rb:207-214` (the `resource :billing` block)
- Modify: `app/controllers/settings/billings_controller.rb`
- Test: `test/controllers/settings/billings_controller_test.rb`

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `resource :billing, only: [] do ... collection do` block, add:

```ruby
        post :create_subscription
```

- [ ] **Step 2: Write the failing test**

In `test/controllers/settings/billings_controller_test.rb`, add. Because confirming a ConfirmationToken is a live-only operation, stub the Stripe confirm calls with WebMock and assert the controller wires the pieces and returns JSON:

```ruby
  test "create_subscription activates the existing subscription and returns json" do
    create_stripe_price(plans(:basic_yearly_3))
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    Billing::Subscription.stub(:subscribe, OpenStruct.new(status: "succeeded")) do
      post :create_subscription, params: {
        plan_id: plans(:basic_yearly_3).id, confirmation_token: "ctoken_123"
      }, format: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "succeeded", body["status"]
    assert_equal plans(:basic_yearly_3), user.reload.plan
  end
```

(`require "ostruct"` at the top of the test file if not already present.)

- [ ] **Step 3: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/settings/billings_controller_test.rb -n /create_subscription/`
Expected: FAIL — no route / action.

- [ ] **Step 4: Implement the action**

In `app/controllers/settings/billings_controller.rb`, add:

```ruby
  def create_subscription
    @user = current_user
    plan = Plan.find(params[:plan_id])

    intent = Billing::Subscription.subscribe(
      customer_id: @user.customer_id,
      subscription_id: @user.stripe_customer.subscription.id,
      price_id: plan.stripe_id,
      trial_end: @user.trial_end,
      confirmation_token: params[:confirmation_token]
    )

    # Persist the plan without re-triggering the price change in update_billing
    # (Billing::Subscription.subscribe already changed the Stripe side).
    @user.skip_billing_plan_change = true
    @user.update(plan: plan)
    Rails.cache.delete(FeedbinUtils.payment_details_key(@user.id))

    if intent.status == "succeeded"
      render json: {status: intent.status}
    else
      render json: {status: intent.status, client_secret: intent.client_secret, requires_action: true}
    end
  rescue Stripe::CardError => exception
    render json: {error: exception.message}, status: :unprocessable_entity
  end
```

> When `intent.status` is `requires_action` (3DS), the Stimulus controller (Task 3.2) calls `stripe.handleNextAction({ clientSecret })` before navigating — already handled by `billing_controller.js`.

- [ ] **Step 5: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/settings/billings_controller_test.rb -n /create_subscription/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/settings/billings_controller.rb test/controllers/settings/billings_controller_test.rb
git commit -m "Add create_subscription deferred-intent endpoint"
```

---

### Task 2.3: Rework `update_credit_card` and `payment_details`

**Files:**
- Modify: `app/controllers/settings/billings_controller.rb` (`update_credit_card` ~47, `payment_details` ~37)
- Test: `test/controllers/settings/billings_controller_test.rb`

- [ ] **Step 1: Rewrite the failing "update credit card" test**

Replace the existing `"should update credit card"` test with:

```ruby
  test "update_credit_card confirms a setup intent and returns json" do
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    Billing::PaymentMethod.stub(:confirm_and_set_default, OpenStruct.new(status: "succeeded")) do
      post :update_credit_card, params: {confirmation_token: "ctoken_123"}, format: :json
    end

    assert_response :success
    assert_equal "succeeded", JSON.parse(response.body)["status"]
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/settings/billings_controller_test.rb -n /update_credit_card/`
Expected: FAIL (old action expects `stripe_token` + redirect).

- [ ] **Step 3: Implement**

Replace `update_credit_card` and `payment_details` in the controller:

```ruby
  def payment_details
    @message = Rails.cache.fetch(FeedbinUtils.payment_details_key(current_user.id), expires_in: 5.minutes) {
      Billing::PaymentMethod.summary(current_user.customer_id)
    }
  rescue
    @message = "No payment info"
  end

  def update_credit_card
    @user = current_user
    if params[:confirmation_token].blank?
      Librato.increment("billing.token_missing")
      return render json: {error: "There was a problem updating your card. Please try again."}, status: :unprocessable_entity
    end

    intent = Billing::PaymentMethod.confirm_and_set_default(
      customer_id: @user.customer_id, confirmation_token: params[:confirmation_token]
    )

    if intent.status == "succeeded"
      Rails.cache.delete(FeedbinUtils.payment_details_key(@user.id))
      @user.update(suspended: false)
      @user.subscriptions.update_all(active: true)
      customer = Billing::Customer.retrieve(@user.customer_id)
      Billing::Subscription.reopen_account(@user.customer_id) if customer.unpaid?
      render json: {status: intent.status}
    else
      render json: {status: intent.status, client_secret: intent.client_secret, requires_action: true}
    end
  rescue Stripe::CardError => exception
    render json: {error: exception.message}, status: :unprocessable_entity
  end
```

- [ ] **Step 4: Bump the payment-details cache key**

In `app/models/feedbin_utils.rb:24`, change `"payment_details:%s:v5"` to `"payment_details:%s:v6"`.

- [ ] **Step 5: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/settings/billings_controller_test.rb -n /update_credit_card/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/settings/billings_controller.rb app/models/feedbin_utils.rb test/controllers/settings/billings_controller_test.rb
git commit -m "Rework update_credit_card and payment_details for SetupIntents"
```

---

## Phase 3 — Stimulus controller + Payment Element + Phlex components

### Task 3.1: `Billing::PaymentElementComponent` (shared mount)

**Files:**
- Create: `app/views/components/billing/payment_element_component.rb`
- Test: `test/components/billing/payment_element_component_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/components/billing/payment_element_component_test.rb`:

```ruby
require "component_test_case"

class Billing::PaymentElementComponentTest < ComponentTestCase
  test "renders the mount point and wires the stimulus controller" do
    html = render Billing::PaymentElementComponent.new(
      publishable_key: "pk_test_1", mode: "setup", amount: 0, currency: "usd",
      endpoint: "/settings/billing/update_credit_card", return_url: "https://feedbin.com/back"
    )
    assert_includes html, 'data-controller="billing"'
    assert_includes html, 'data-billing-publishable-key-value="pk_test_1"'
    assert_includes html, 'data-billing-target="paymentElement"'
  end
end
```

(Confirm `ComponentTestCase`/`component_test_case.rb` is the existing base — it is required in `test_helper.rb`.)

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/payment_element_component_test.rb`
Expected: FAIL — `uninitialized constant Billing::PaymentElementComponent`.

- [ ] **Step 3: Implement**

Create `app/views/components/billing/payment_element_component.rb`:

```ruby
module Billing
  class PaymentElementComponent < ApplicationComponent
    def initialize(publishable_key:, mode:, amount:, currency:, endpoint:, return_url:, default_plan_id: nil)
      @publishable_key = publishable_key
      @mode = mode
      @amount = amount
      @currency = currency
      @endpoint = endpoint
      @return_url = return_url
      @default_plan_id = default_plan_id
    end

    def view_template
      div(
        data: stimulus(
          controller: :billing,
          values: {
            publishable_key: @publishable_key,
            mode: @mode,
            amount: @amount,
            currency: @currency,
            endpoint: @endpoint,
            return_url: @return_url,
            default_plan: @default_plan_id
          }
        )
      ) do
        div(id: "payment-element", data: stimulus_item(target: :payment_element, for: :billing))
        div(class: "text-red-600 mt-2 hidden", data: stimulus_item(target: :error, for: :billing))
        yield if block_given?
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/payment_element_component_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/components/billing/payment_element_component.rb test/components/billing/payment_element_component_test.rb
git commit -m "Add Billing::PaymentElementComponent"
```

---

### Task 3.2: `billing_controller.js` Stimulus controller

**Files:**
- Create: `app/javascript/controllers/billing_controller.js`
- Delete: `app/assets/javascripts/payments/payments.js.coffee.erb`

- [ ] **Step 1: Implement the controller**

Create `app/javascript/controllers/billing_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="billing"
export default class extends Controller {
  static targets = ["paymentElement", "error", "submit", "planInput"]
  static values = {
    publishableKey: String,
    mode: String,
    amount: Number,
    currency: String,
    endpoint: String,
    returnUrl: String,
    defaultPlan: Number
  }

  async connect() {
    this.stripe = Stripe(this.publishableKeyValue)
    this.elements = this.stripe.elements({
      mode: this.modeValue,
      currency: this.currencyValue,
      amount: this.amountValue > 0 ? this.amountValue : undefined,
      setupFutureUsage: this.modeValue === "subscription" ? "off_session" : undefined,
      appearance: this.appearance()
    })
    this.paymentElement = this.elements.create("payment")
    this.paymentElement.mount(this.paymentElementTarget)
  }

  planChanged(event) {
    const amount = parseInt(event.target.dataset.amount, 10)
    if (amount > 0) {
      this.elements.update({ amount })
    }
  }

  async submit(event) {
    event.preventDefault()
    this.setBusy(true)

    const { error: submitError } = await this.elements.submit()
    if (submitError) return this.fail(submitError.message)

    const { error: tokenError, confirmationToken } =
      await this.stripe.createConfirmationToken({ elements: this.elements })
    if (tokenError) return this.fail(tokenError.message)

    const payload = { confirmation_token: confirmationToken.id }
    if (this.hasPlanInputTarget) payload.plan_id = this.selectedPlanId()

    const response = await fetch(this.endpointValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "application/json"
      },
      body: JSON.stringify(payload)
    })
    const data = await response.json()

    if (!response.ok) return this.fail(data.error || "Payment failed.")

    if (data.requires_action && data.client_secret) {
      const { error } = await this.stripe.handleNextAction({ clientSecret: data.client_secret })
      if (error) return this.fail(error.message)
    }

    window.location = this.returnUrlValue
  }

  selectedPlanId() {
    const checked = this.planInputTargets.find((input) => input.checked)
    return checked ? checked.value : this.defaultPlanValue
  }

  appearance() {
    const dark = ["dusk", "midnight"].includes(window.feedbin?.theme) || window.feedbin?.darkMode?.()
    return { theme: dark ? "night" : "stripe" }
  }

  setBusy(busy) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = busy
  }

  fail(message) {
    this.setBusy(false)
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
  }
}
```

- [ ] **Step 2: Remove the old CoffeeScript**

```bash
git rm app/assets/javascripts/payments/payments.js.coffee.erb
```

Search for any include of the old asset: `source ~/.bash_profile && grep -rn "payments" app/views config | grep -i "javascript_include_tag\|payments"`. Those includes are removed in Task 3.3/3.4 when the views are converted.

- [ ] **Step 3: Verify the controller registers**

Run: `source ~/.bash_profile && grep -rn "billing" app/javascript/controllers/index.js` (if controllers are eager-globbed this may be automatic — confirm by matching the pattern used by `tabs_controller.js`). If `index.js` lists controllers explicitly, add the `billing` registration following the existing pattern.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/billing_controller.js app/javascript/controllers/index.js
git commit -m "Add billing Stimulus controller, remove CoffeeScript payments"
```

---

### Task 3.3: `Billing::UpdateCardComponent` + convert `billings/edit`

**Files:**
- Create: `app/views/components/billing/update_card_component.rb`
- Modify: `app/views/settings/billings/edit.html.erb` (render the component)
- Test: `test/components/billing/update_card_component_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/components/billing/update_card_component_test.rb`:

```ruby
require "component_test_case"

class Billing::UpdateCardComponentTest < ComponentTestCase
  test "renders an update form using the payment element in setup mode" do
    html = render Billing::UpdateCardComponent.new(publishable_key: "pk_test_1")
    assert_includes html, 'data-billing-mode-value="setup"'
    assert_includes html, "Update"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/update_card_component_test.rb`
Expected: FAIL — constant missing.

- [ ] **Step 3: Implement**

Create `app/views/components/billing/update_card_component.rb`:

```ruby
module Billing
  class UpdateCardComponent < ApplicationComponent
    include Phlex::Rails::Helpers::Routes

    def initialize(publishable_key:)
      @publishable_key = publishable_key
    end

    def view_template
      render Settings::H1Component.new { "Billing" }

      form(data: stimulus_item(actions: {submit: :submit}, for: :billing)) do
        render Billing::PaymentElementComponent.new(
          publishable_key: @publishable_key,
          mode: "setup",
          amount: 0,
          currency: "usd",
          endpoint: update_credit_card_settings_billing_path,
          return_url: settings_billing_url
        )

        render Settings::ButtonRowComponent.new do
          button(
            type: "submit", class: "button",
            data: stimulus_item(target: :submit, for: :billing)
          ) { "Update" }
        end
      end
    end
  end
end
```

Replace `app/views/settings/billings/edit.html.erb` with:

```erb
<%= render Billing::UpdateCardComponent.new(publishable_key: STRIPE_PUBLIC_KEY) %>
<% content_for :head do %>
  <%= javascript_include_tag "https://js.stripe.com/v3/" %>
<% end %>
```

- [ ] **Step 4: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/update_card_component_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/components/billing/update_card_component.rb app/views/settings/billings/edit.html.erb test/components/billing/update_card_component_test.rb
git commit -m "Add Billing::UpdateCardComponent and convert billings/edit"
```

---

### Task 3.4: `Billing::SubscribeFormComponent` + convert `index`

**Files:**
- Create: `app/views/components/billing/subscribe_form_component.rb`
- Modify: `app/views/settings/billings/index.html.erb`
- Delete: `app/views/shared/billing/_billing_subscribe.html.erb`, `app/views/shared/_credit_card_form.html.erb`
- Test: `test/components/billing/subscribe_form_component_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/components/billing/subscribe_form_component_test.rb`:

```ruby
require "component_test_case"

class Billing::SubscribeFormComponentTest < ComponentTestCase
  test "renders plan radios and a payment-mode element for an immediate charge" do
    plan = plans(:basic_yearly_3)
    html = render Billing::SubscribeFormComponent.new(
      publishable_key: "pk_test_1", plans: [plan], default_plan: plan,
      subscribe_title: "Plan", mode: "payment"
    )
    assert_includes html, 'data-billing-mode-value="payment"'
    assert_includes html, "Plan"
    assert_includes html, 'data-billing-target="planInput"'
  end

  test "uses setup mode and zero amount for a future trial" do
    plan = plans(:basic_yearly_3)
    html = render Billing::SubscribeFormComponent.new(
      publishable_key: "pk_test_1", plans: [plan], default_plan: plan,
      subscribe_title: "Plan", mode: "setup"
    )
    assert_includes html, 'data-billing-mode-value="setup"'
    assert_includes html, 'data-billing-amount-value="0"'
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/subscribe_form_component_test.rb`
Expected: FAIL — constant missing.

- [ ] **Step 3: Implement**

Create `app/views/components/billing/subscribe_form_component.rb`:

```ruby
module Billing
  class SubscribeFormComponent < ApplicationComponent
    include Phlex::Rails::Helpers::Routes
    register_value_helper :number_to_currency

    def initialize(publishable_key:, plans:, default_plan:, subscribe_title:, mode:)
      @publishable_key = publishable_key
      @plans = plans
      @default_plan = default_plan
      @subscribe_title = subscribe_title
      @mode = mode # "setup" for a future trial, "payment" for an immediate charge
    end

    def view_template
      form(data: stimulus_item(actions: {submit: :submit}, for: :billing)) do
        render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
          group.header { @subscribe_title }
          @plans.each { |plan| render_plan_row(group, plan) }
        end

        render Billing::PaymentElementComponent.new(
          publishable_key: @publishable_key,
          mode: @mode,
          amount: @mode == "payment" ? @default_plan.price_in_cents : 0,
          currency: "usd",
          endpoint: create_subscription_settings_billing_path,
          return_url: settings_billing_url,
          default_plan_id: @default_plan.id
        )

        render Settings::ButtonRowComponent.new do
          button(type: "submit", class: "button no-margin",
                 data: stimulus_item(target: :submit, for: :billing)) { "Subscribe" }
        end
      end
    end

    private

    def render_plan_row(group, plan)
      group.item do
        input(
          type: "radio", name: "plan_id", id: dom_id(plan), value: plan.id,
          class: "peer", checked: plan == @default_plan,
          data: stimulus_item(target: :plan_input, actions: {change: :plan_changed}, for: :billing).merge(amount: plan.price_in_cents)
        )
        label(for: dom_id(plan), class: "group") do
          render Settings::ControlRowComponent.new do |row|
            row.title { "#{number_to_currency(plan.price, precision: 0)}/#{plan.period}" }
            row.control { render Form::RadioComponent.new }
          end
        end
      end
    end
  end
end
```

Replace `app/views/settings/billings/index.html.erb` with:

```erb
<% content_for :head do %>
  <%= javascript_include_tag "https://js.stripe.com/v3/" %>
<% end %>

<% if ENV["STRIPE_API_KEY"] %>
  <% if @user.plan.stripe_id == "trial" %>
    <%= render Billing::SubscribeFormComponent.new(
          publishable_key: STRIPE_PUBLIC_KEY,
          plans: @plans, default_plan: @default_plan, subscribe_title: "Plan",
          mode: @user.trial_end.future? ? "setup" : "payment") %>
  <% else %>
    <%= render Billing::StatusComponent.new(user: @user) %>
  <% end %>
  <script>$.get("<%= payment_details_settings_billing_path %>");</script>
<% else %>
  <p>Billing disabled. <code>STRIPE_API_KEY</code> and <code>STRIPE_PUBLIC_KEY</code> are missing.</p>
<% end %>
```

> `Billing::StatusComponent` is built in Task 4.3. Until then, temporarily keep the old `render partial: "shared/billing/billing_status"` on the `else` branch so the page renders; swap to the component in Task 4.3.

In `index.html.erb` the controller's `index` action also calls `plan_setup`, which sets `@plans`/`@default_plan`. Confirm `@default_plan` is set on the trial branch (it is set in `payments`/`plan_setup`). Set `@default_plan ||= @plans.first` in the controller `index` if nil.

Delete the old partials:

```bash
git rm app/views/shared/billing/_billing_subscribe.html.erb app/views/shared/_credit_card_form.html.erb
```

- [ ] **Step 4: Run component + controller tests**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/subscribe_form_component_test.rb test/controllers/settings/billings_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add Billing::SubscribeFormComponent and convert billings index"
```

---

## Phase 4 — Webhooks, BillingEvent, payment history

### Task 4.1: Migrate payment-history parsing

**Files:**
- Modify: `app/controllers/settings/billings_controller.rb` (`payments` ~70-88)
- Test: `test/controllers/settings/billings_controller_test.rb`

- [ ] **Step 1: Update the webhook fixtures for the new API version**

Replace `StripeMock.mock_webhook_event` in the controller test with static fixtures. Create `test/fixtures/stripe_webhooks/invoice_payment_succeeded.json` and `charge_succeeded.json` by capturing real events from the live test account for `2026-05-27.dahlia`:

```bash
source ~/.bash_profile && stripe events list --limit 1 --type invoice.payment_succeeded > test/fixtures/stripe_webhooks/invoice_payment_succeeded.json
```

(Or hand-build minimal JSON matching the shapes recorded in `docs/superpowers/notes/stripe-api-shapes.md`.) Add a helper in `test_helper.rb`:

```ruby
  def stripe_webhook_event(name, customer:)
    data = JSON.parse(File.read("test/fixtures/stripe_webhooks/#{name}.json"))
    data["data"]["object"]["customer"] = customer
    data["id"] ||= "evt_#{SecureRandom.hex(8)}"
    data
  end
```

- [ ] **Step 2: Rewrite the "should get billing" / "payment_history" tests to use fixtures**

Replace the `StripeMock.mock_webhook_event(...)` calls with `stripe_webhook_event("charge_succeeded", customer: @user.customer_id)` etc., and drop `StripeMock.start`/`StripeMock.stop`.

- [ ] **Step 3: Run to verify they fail against the new parser**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/settings/billings_controller_test.rb -n /billing/`
Expected: FAIL where `@next_payment_date` parsing relies on the old `lines.data[].type == "subscription"` shape.

- [ ] **Step 4: Update `payments` to the new line-item shape**

In `app/controllers/settings/billings_controller.rb`, update the `@next_payment_date` extraction to match the confirmed shape from Task 0.3. Using the dahlia line-item shape (period on the line, subscription detected via `parent`):

```ruby
    if @next_payment.present? && !@user.timed_plan? && !@user.app_plan?
      @next_payment.first.event_object["lines"]["data"].each do |line|
        if line.dig("parent", "subscription_item_details") || line["subscription"]
          @next_payment_date = Time.at(line["period"]["end"]).utc.to_datetime
        end
      end
    end
```

> Adjust the `if` condition to the exact field recorded in the notes doc.

- [ ] **Step 5: Run to verify they pass**

Run: `source ~/.bash_profile && bundle exec rails test test/controllers/settings/billings_controller_test.rb -n /billing/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Migrate payment-history parsing to new invoice line-item shape"
```

---

### Task 4.2: Verify `BillingEvent` and `UpdateStatementDescriptor` under the new API

**Files:**
- Modify: `app/models/billing_event.rb` (only fields that changed)
- Modify: `app/jobs/update_statement_descriptor.rb` (if `statement_descriptor` access changed)
- Test: `test/models/billing_event_test.rb`, `test/jobs/update_statement_descriptor_test.rb`

- [ ] **Step 1: Convert existing tests to fixtures**

In `test/models/billing_event_test.rb` and `test/jobs/update_statement_descriptor_test.rb`, replace `StripeMock.mock_webhook_event` with `stripe_webhook_event(...)` fixtures (add `invoice_created.json`, `invoice_upcoming.json`, `customer_subscription_updated.json` fixtures captured as in Task 4.1).

- [ ] **Step 2: Run to find breakages**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing_event_test.rb test/jobs/update_statement_descriptor_test.rb`
Expected: some FAIL where event field names changed (e.g. `invoice.subscription`, `amount_remaining`, `period_end`).

- [ ] **Step 3: Fix only the changed accessors**

Update `BillingEvent#invoice`/`#invoice_items` (`Stripe::Invoice.retrieve(...).lines.list`), `subscription_reminder?` (`amount_remaining`), `period_end`, and the subscription-status checks to the confirmed shapes. In `update_statement_descriptor.rb`, confirm `Stripe::Invoice.update(id, {statement_descriptor:})` still accepts the field; if renamed under dahlia, use the documented replacement.

- [ ] **Step 4: Run to verify they pass**

Run: `source ~/.bash_profile && bundle exec rails test test/models/billing_event_test.rb test/jobs/update_statement_descriptor_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Migrate BillingEvent and statement descriptor to new API shapes"
```

---

### Task 4.3: `Billing::StatusComponent` (convert remaining billing views)

**Files:**
- Create: `app/views/components/billing/status_component.rb`
- Modify: `app/views/settings/billings/index.html.erb` (use the component)
- Delete: `app/views/shared/billing/_billing_status.html.erb` and the `plan_free`/`plan_timed`/`plan_app`/`plan_default` partials
- Test: `test/components/billing/status_component_test.rb`

- [ ] **Step 1: Read the four `plan_*` partials**

Run: `source ~/.bash_profile && for f in plan_free plan_timed plan_app plan_default; do echo "=== $f ==="; cat app/views/shared/billing/_$f.html.erb; done`
Reproduce each partial's markup as a private method in the component (keep wording/links identical).

- [ ] **Step 2: Write the failing test**

Create `test/components/billing/status_component_test.rb`:

```ruby
require "component_test_case"

class Billing::StatusComponentTest < ComponentTestCase
  test "renders the default plan status for a subscribed user" do
    user = users(:ben)
    html = render Billing::StatusComponent.new(user: user)
    assert html.present?
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/status_component_test.rb`
Expected: FAIL — constant missing.

- [ ] **Step 4: Implement**

Create `app/views/components/billing/status_component.rb` selecting the branch (`free` / `timed?` / `app?` / default) and rendering the corresponding markup reproduced in Step 1. Then point `index.html.erb`'s `else` branch at `Billing::StatusComponent.new(user: @user)` and delete the partials:

```bash
git rm app/views/shared/billing/_billing_status.html.erb app/views/shared/billing/_plan_free.html.erb app/views/shared/billing/_plan_timed.html.erb app/views/shared/billing/_plan_app.html.erb app/views/shared/billing/_plan_default.html.erb
```

- [ ] **Step 5: Run to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/components/billing/status_component_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add Billing::StatusComponent and remove billing status partials"
```

---

## Phase 5 — Full-suite green & cleanup

### Task 5.1: Run the full suite and fix stragglers

**Files:** as needed (`api/v2/users_controller_test`, `trial_expiration_test`, `user_deleter_test`, `app_store_notification_processor_test`).

- [ ] **Step 1: Run the full suite**

Run (with stripe-mock running): `source ~/.bash_profile && bundle exec rake`
Expected: identify any remaining failures referencing removed code (`StripeMock`, `Customer`, `stripe_token`, `customer.sources`).

- [ ] **Step 2: Fix each failing test**

For each failure, convert any remaining `StripeMock`/token usage to stripe-mock + the `Billing::` services, matching the patterns from earlier tasks. Do not weaken assertions — adjust them to the new shapes.

- [ ] **Step 3: Re-run until green**

Run: `source ~/.bash_profile && bundle exec rake`
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 4: Final dead-code sweep**

Run: `source ~/.bash_profile && grep -rn "StripeMock\|stripe-ruby-mock\|payments.js.coffee\|stripe_token\|customer\.sources\|Customer\.create\|Customer\.retrieve" app lib test config Gemfile`
Expected: no matches (or only intentional ones). Remove any leftover references.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Green full suite on modernized Stripe integration"
```

---

### Task 5.2: Manual verification checklist (real Stripe test mode)

- [ ] Subscribe flow during a future-dated trial → SetupIntent path; subscription becomes `trialing`; no charge; card on file.
- [ ] Subscribe flow with an expired trial → PaymentIntent path; immediate charge succeeds.
- [ ] 3DS test card (`4000 0027 6000 3184`) → `handleNextAction` triggers and completes.
- [ ] Update card on an active subscription → default PM changes; `payment_details` reflects new card after cache clear.
- [ ] Apple Pay / Google Pay appears in the Payment Element on supported browsers.
- [ ] Webhook receipt: trigger `invoice.payment_succeeded` via `stripe trigger` → `BillingEvent` created, receipt mail enqueued, payment history shows the entry and next-payment date.

---

## Notes for the implementer

- **stripe-mock must be running** for every test command in this plan. Start it once: `stripe-mock -http-port 12111`.
- Where a task says "adjust to the shape confirmed in Task 0.3," that confirmation is mandatory before writing the dependent code — those are the spec's named risk areas (invoice→subscription linkage, line-item `type`, deferred-confirm support).
- Keep commits per-task; the suite should be green at every commit from Task 1.1 onward (Phase 0 tasks may leave specific older tests temporarily red until their conversion task).
