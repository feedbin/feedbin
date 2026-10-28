require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "reopen_account voids the invoice it re-anchors past" do
    invoice = stripe_invoice(status: "open", attempt_count: 4)
    voided = []
    updated = []

    with_reopen_stubs(invoice, voided, updated) do
      assert_equal :reanchored, customer.reopen_account
    end

    assert_equal ["in_lapsed"], voided, "the abandoned period should not stay outstanding"
    assert_equal ["sub_test"], updated
  end

  test "reopen_account has nothing to void when the invoice is still a draft" do
    invoice = stripe_invoice(status: "draft", attempt_count: 0)
    voided = []
    updated = []

    with_reopen_stubs(invoice, voided, updated) do
      assert_equal :reanchored, customer.reopen_account
    end

    assert_empty voided, "voiding is only valid on an open invoice"
    assert_equal ["sub_test"], updated
  end

  test "reopen_account reports reopening rather than re-anchoring when it un-closes" do
    invoice = stripe_invoice(status: "open", attempt_count: 1, closed: true)
    voided = []
    updated = []

    with_reopen_stubs(invoice, voided, updated) do
      assert_equal :reopened, customer.reopen_account
    end

    assert_empty voided, "an un-closed invoice is meant to be collected, not written off"
    assert_empty updated
  end

  test "pay_open_invoice treats an invoice paid out from under it as paid" do
    responses = [
      Stripe::Invoice.construct_from(id: "in_open", object: "invoice", status: "open"),
      Stripe::Invoice.construct_from(id: "in_open", object: "invoice", status: "paid")
    ]
    pay = ->(*) { raise Stripe::InvalidRequestError.new("Invoice is already paid", nil) }

    Customer.stub_any_instance(:subscription, dunning_subscription) do
      Stripe::Invoice.stub(:retrieve, ->(*) { responses.shift }) do
        Stripe::Invoice.stub(:pay, pay) do
          assert_equal :paid, customer.pay_open_invoice
        end
      end
    end
  end

  test "pay_open_invoice re-raises when the invoice turns out not to be paid" do
    invoice = Stripe::Invoice.construct_from(id: "in_open", object: "invoice", status: "open")
    pay = ->(*) { raise Stripe::InvalidRequestError.new("No such invoice", nil) }

    Customer.stub_any_instance(:subscription, dunning_subscription) do
      Stripe::Invoice.stub(:retrieve, invoice) do
        Stripe::Invoice.stub(:pay, pay) do
          assert_raises(Stripe::InvalidRequestError) { customer.pay_open_invoice }
        end
      end
    end
  end

  test "reopen_account lets a re-anchor that needs authentication through, then collects the fresh invoice" do
    lapsed = stripe_invoice(status: "open", attempt_count: 4)
    invoices = Stripe::ListObject.construct_from(object: "list", has_more: false, data: [lapsed])
    reanchored = Stripe::StripeObject.construct_from(id: "sub_test", object: "subscription", latest_invoice: "in_fresh")
    fresh = Stripe::Invoice.construct_from(id: "in_fresh", object: "invoice", status: "open")
    update_params = []
    paid = []
    pay = ->(id, *) {
      paid << id
      raise Stripe::CardError.new("Authentication required", nil, code: "invoice_payment_intent_requires_action")
    }

    stripe_customer = customer
    Stripe::Invoice.stub(:list, invoices) do
      Stripe::Invoice.stub(:void_invoice, nil) do
        Stripe::Subscription.stub(:update, ->(_id, params) { update_params << params; reanchored }) do
          Stripe::Invoice.stub(:retrieve, fresh) do
            Stripe::Invoice.stub(:pay, pay) do
              assert_equal :reanchored, stripe_customer.reopen_account
              assert_equal :requires_action, stripe_customer.pay_open_invoice
            end
          end
        end
      end
    end

    assert_equal "allow_incomplete", update_params.first[:payment_behavior], "Stripe refuses the whole update without it when the bank wants a challenge"
    assert_equal ["in_fresh"], paid, "only the re-anchored period's invoice is owed"
  end

  test "update_plan applies the change even when the charge needs authentication" do
    saved = []

    with_plan_change_stubs(saved, invoice_status: "open", intent_status: "requires_action") do
      assert_equal :requires_action, customer.update_plan("basic-yearly-3", Time.now - 1.day)
    end

    assert_equal [{payment_behavior: "allow_incomplete"}], saved
  end

  test "update_plan reports a declined charge" do
    with_plan_change_stubs([], invoice_status: "open", intent_status: "requires_payment_method") do
      assert_equal :declined, customer.update_plan("basic-yearly-3", Time.now - 1.day)
    end
  end

  test "update_plan reports nothing owed when the charge went through" do
    with_plan_change_stubs([], invoice_status: "paid", intent_status: "succeeded") do
      assert_nil customer.update_plan("basic-yearly-3", Time.now - 1.day)
    end
  end

  private

  def with_plan_change_stubs(saved, invoice_status:, intent_status:)
    subscription = Stripe::Subscription.construct_from(id: "sub_test", object: "subscription", plan: "trial", trial_end: nil, latest_invoice: "in_plan_change")
    invoice = Stripe::Invoice.construct_from(id: "in_plan_change", object: "invoice", status: invoice_status, payment_intent: "pi_plan_change")
    intent = Stripe::PaymentIntent.construct_from(id: "pi_plan_change", object: "payment_intent", status: intent_status, client_secret: "pi_secret")

    subscription.stub(:save, ->(params = {}) { saved << params; subscription }) do
      Customer.stub_any_instance(:subscription, subscription) do
        Stripe::Invoice.stub(:retrieve, invoice) do
          Stripe::PaymentIntent.stub(:retrieve, intent) do
            yield
          end
        end
      end
    end
  end

  def dunning_subscription
    Stripe::StripeObject.construct_from(id: "sub_test", object: "subscription", latest_invoice: "in_open")
  end

  def customer
    Customer.new(Stripe::Customer.construct_from(id: "cus_test", object: "customer"))
  end

  def stripe_invoice(status:, attempt_count:, closed: false)
    Stripe::Invoice.construct_from(
      id: "in_lapsed",
      object: "invoice",
      status: status,
      paid: false,
      closed: closed,
      attempt_count: attempt_count,
      subscription: "sub_test"
    )
  end

  def with_reopen_stubs(invoice, voided, updated)
    invoices = Stripe::ListObject.construct_from(object: "list", has_more: false, data: [invoice])

    Stripe::Invoice.stub(:list, invoices) do
      Stripe::Invoice.stub(:void_invoice, ->(id, *) { voided << id }) do
        Stripe::Subscription.stub(:update, ->(id, *) { updated << id }) do
          invoice.stub(:save, invoice) do
            yield
          end
        end
      end
    end
  end
end
