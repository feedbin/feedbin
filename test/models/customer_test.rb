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

  private

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
