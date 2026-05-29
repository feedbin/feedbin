# Stripe object shapes under API version `2026-05-27.dahlia`

Reference doc produced by Task 0.3 (discovery) of the Stripe modernization plan
(`docs/superpowers/plans/2026-05-29-stripe-modernization.md`).

Environment: `stripe` gem **19.2.0**, API version pinned to **2026-05-27.dahlia**,
shapes captured against **stripe-mock 0.201.0** plus the live Stripe API reference
(via the Stripe docs MCP tool). `2026-05-27.dahlia` is post-Basil
(`2025-06-30.basil`), so all Basil-era billing breaking changes apply.

Consumed by:
- Task 1.5 — subscription confirm path (getting the PaymentIntent/SetupIntent client secret from `latest_invoice` / `pending_setup_intent`)
- Task 4.1 — payment-history line-item parsing
- Task 4.2 — `BillingEvent` invoice→subscription linkage, `statement_descriptor`

---

## Step 1 — raw stripe-mock output (the KEYS lines)

Captured with `payment_behavior: "default_incomplete"` and
`expand: ["latest_invoice.payment_intent", "pending_setup_intent"]`. NOTE: the
`latest_invoice.payment_intent` expand path did **not** raise against stripe-mock,
but the resulting `Stripe::Invoice` does **not** respond to `payment_intent`
(see Fact 3) — the expand was silently a no-op.

```
SUBSCRIPTION KEYS: [:application, :application_fee_percent, :automatic_tax, :billing_cycle_anchor, :billing_cycle_anchor_config, :billing_mode, :billing_schedules, :billing_thresholds, :cancel_at, :cancel_at_period_end, :canceled_at, :cancellation_details, :collection_method, :created, :currency, :customer, :customer_account, :days_until_due, :default_payment_method, :default_source, :default_tax_rates, :description, :discounts, :ended_at, :id, :invoice_settings, :items, :latest_invoice, :livemode, :managed_payments, :metadata, :next_pending_invoice_item_invoice, :object, :on_behalf_of, :pause_collection, :payment_settings, :pending_invoice_item_interval, :pending_setup_intent, :pending_update, :schedule, :start_date, :status, :test_clock, :transfer_data, :trial_end, :trial_settings, :trial_start]

ITEM KEYS: [:billing_thresholds, :created, :current_period_end, :current_period_start, :discounts, :id, :metadata, :object, :price, :quantity, :subscription, :tax_rates]

INVOICE KEYS: [:account_country, :account_name, :account_tax_ids, :amount_due, :amount_overpaid, :amount_paid, :amount_paid_off_stripe, :amount_remaining, :amount_shipping, :application, :attempt_count, :attempted, :auto_advance, :automatic_tax, :automatically_finalizes_at, :billing_reason, :collection_method, :created, :currency, :custom_fields, :customer, :customer_account, :customer_address, :customer_email, :customer_name, :customer_phone, :customer_shipping, :customer_tax_exempt, :customer_tax_ids, :default_payment_method, :default_source, :default_tax_rates, :description, :discounts, :due_date, :effective_at, :ending_balance, :footer, :from_invoice, :hosted_invoice_url, :id, :invoice_pdf, :issuer, :last_finalization_error, :latest_revision, :lines, :livemode, :metadata, :next_payment_attempt, :number, :object, :on_behalf_of, :parent, :payment_settings, :period_end, :period_start, :post_payment_credit_notes_amount, :pre_payment_credit_notes_amount, :receipt_number, :rendering, :shipping_cost, :shipping_details, :starting_balance, :statement_descriptor, :status, :status_transitions, :subtotal, :subtotal_excluding_tax, :test_clock, :total, :total_discount_amounts, :total_excluding_tax, :total_pretax_credit_amounts, :total_taxes, :webhooks_delivered_at]

INVOICE LINE KEYS: [:amount, :currency, :description, :discount_amounts, :discountable, :discounts, :id, :invoice, :livemode, :metadata, :object, :parent, :period, :pretax_credit_amounts, :pricing, :quantity, :quantity_decimal, :subscription, :subtotal, :taxes]
```

### Supplementary deep-inspection output (stripe-mock)

```
sub.pending_setup_intent          => Stripe::SetupIntent (present, expandable; id seti_...)
sub.latest_invoice                => Stripe::Invoice (expandable)
inv.respond_to?(:confirmation_secret) => true   (value nil with stripe-mock canned data)
inv.respond_to?(:payment_intent)      => false  (field no longer exists on the object)
inv.parent  => { type: "quote_details",
                 subscription_details: { metadata: nil, subscription: "subscription" },
                 quote_details: { quote: "quote" } }
                 # NOTE: stripe-mock returns canned type="quote_details"; live a
                 # subscription invoice has type="subscription_details".
line.parent => { type: "invoice_item_details",
                 subscription_item_details: { subscription: "subscription",
                                              subscription_item: "subscription_item",
                                              proration: true, ... },
                 invoice_item_details: { ... } }
line.period => { start: <unix>, end: <unix> }
line.subscription => nil   # top-level line.subscription is null; use line.parent.subscription_item_details.subscription
line.pricing  => { type: "price_details", unit_amount_decimal: nil }
line.type     => NoMethodError  (the `type` accessor no longer exists on invoice line items)
```

Top-level convenience fields `invoice.subscription` and `line.type` are **gone**
from the object (no key, accessor raises / is absent). `subscription` does still
appear as a key on the **subscription item** (`sub.items.data.first`) and as a
(null in mock) key on the **invoice line**, but the authoritative linkage lives
under `parent` (see Facts 1 & 2).

---

## Confirmed facts

### Fact 1 — invoice → subscription linkage

**An invoice is linked to its subscription via
`invoice.parent.subscription_details.subscription`.** First check
`invoice.parent&.type == "subscription_details"`; the subscription id is then at
`invoice.parent.subscription_details.subscription`. The legacy top-level
`invoice.subscription` field was **removed in API `2025-03-31.basil`** and is not
present under `2026-05-27.dahlia`.
_Source: Stripe docs (API ref + breaking-changes guidance: "verify
invoice.parent.type is subscription_details, then use
invoice.parent.subscription_details.subscription instead of invoice.subscription").
stripe-mock confirms `invoice.parent.subscription_details.subscription` exists and
that there is no `invoice.subscription` key._ To expand it, expand
`parent.subscription_details` (or `parent.subscription_details.subscription`).

### Fact 2 — identifying the subscription line item & its billing period

**Invoice line items no longer expose `type == "subscription"`** — the `type`
accessor is gone (stripe-mock: `line.type` raises `NoMethodError`; not in keys).
Identify the subscription line via the `parent` discriminator:
`line.parent.type == "subscription_item_details"`, with the subscription id at
`line.parent.subscription_item_details.subscription` (and the item id at
`line.parent.subscription_item_details.subscription_item`). The other parent type
is `invoice_item_details`. **The billing period still lives on the line itself at
`line.period.start` / `line.period.end`** (unix timestamps).
_Source: stripe-mock output (line.parent.subscription_item_details.subscription,
line.period.start/end present; line.type absent) + Stripe Basil breaking-changes
docs._

### Fact 3 — confirming the first payment (default_incomplete)

**Trialing subscription:** the intent is exposed as
`subscription.pending_setup_intent`, a **`Stripe::SetupIntent`**; use its
`.client_secret` to confirm/collect the payment method on the frontend. On a trial,
`latest_invoice` has no amount due, so there is no first PaymentIntent.
_Source: stripe-mock (`sub.pending_setup_intent` is a populated
`Stripe::SetupIntent`) + Stripe docs ("for a free trial, expand pending_setup_intent
... use the pending_setup_intent's client_secret")._

**Immediate (non-trial) subscription:** the legacy `latest_invoice.payment_intent`
field is **removed** under Basil+/dahlia (stripe-mock: the `Stripe::Invoice` does
**not** respond to `payment_intent`). Instead expand
**`latest_invoice.confirmation_secret`**. `confirmation_secret` contains:
- `confirmation_secret.client_secret` — the secret to confirm on the frontend
- `confirmation_secret.type` — indicates whether the underlying intent is a
  PaymentIntent or a SetupIntent
_Source: Stripe docs ("With Basil, expand latest_invoice.confirmation_secret instead
of latest_invoice.payment_intent. The confirmation_secret has a type parameter
indicating whether it's a PaymentIntent or SetupIntent"). stripe-mock corroborates:
`inv.respond_to?(:confirmation_secret)` is true and `:payment_intent` is false._

Practical guidance for Task 1.5: create the subscription with
`expand: ["latest_invoice.confirmation_secret", "pending_setup_intent"]`. If
`pending_setup_intent` is present (trial), use its `client_secret`; otherwise read
`latest_invoice.confirmation_secret.client_secret` (branch on
`confirmation_secret.type` if you need to call the right confirm method). NOTE: if a
PaymentIntent **id** (`pi_...`) is required (not just the client secret), it is no
longer directly on the invoice — `confirmation_secret` exposes the secret, not the
id. **UNVERIFIED — confirm against live test mode** whether the PaymentIntent id can
be recovered (e.g. by parsing the `pi_..._secret_...` client_secret prefix, or by a
separate `PaymentIntent` lookup). stripe-mock returns nil for `confirmation_secret`
so the exact sub-shape could not be observed live here.

### Fact 4 — `Invoice.update(statement_descriptor:)`

**`statement_descriptor` is still a valid Invoice field and is still accepted by
`Stripe::Invoice.update`** (it can even be updated after finalization). It was not
renamed/moved in recent versions — the old rename (`statement_description` →
`statement_descriptor`) happened back at API `2014-12-17`. stripe-mock confirms
`statement_descriptor` is present on the Invoice object.
_Source: Stripe docs (Invoice object reference lists statement_descriptor; billing
KB notes invoice statement_descriptor is used for the associated charge and can be
updated after finalization) + stripe-mock (`:statement_descriptor` in INVOICE KEYS)._

---

## Step 3 — legacy plan ids resolve as Price ids (LIVE test mode)

**Step 3 NOT RUN — no live `STRIPE_API_KEY` available in this environment; must be
confirmed by the maintainer before relying on legacy ids as Price ids.**

When a key is available, run (per the task spec):

```ruby
require "stripe"; Stripe.api_key = ENV["STRIPE_API_KEY"]; Stripe.api_version = "2026-05-27.dahlia"
%w[basic-monthly basic-yearly basic-monthly-2 basic-yearly-2 basic-monthly-3 basic-yearly-3].each do |id|
  begin; p = Stripe::Price.retrieve(id); puts "#{id} => OK unit_amount=#{p.unit_amount}"; rescue => e; puts "#{id} => MISSING (#{e.class})"; end
end
```

If any id returns MISSING, the implementation must create `Stripe::Price` objects
for those legacy ids before they can be used as Price ids.

---

## Discrepancies / cautions

- stripe-mock returns canned/static data for nested fields: `invoice.parent.type`
  comes back as `"quote_details"` (not `"subscription_details"`), and
  `confirmation_secret` / `line.subscription` come back nil. Trust the **docs** for
  the live shapes; stripe-mock is only authoritative for *which keys/accessors
  exist* on the gem objects under this API version.
- The `latest_invoice.payment_intent` expand path does not raise against stripe-mock
  but is a dead field — do not rely on it; use `confirmation_secret`.
- One item marked **UNVERIFIED** above: recovering a PaymentIntent **id** (vs client
  secret) from `latest_invoice.confirmation_secret` — confirm against live test mode
  for Task 1.5 if an id is actually needed.
