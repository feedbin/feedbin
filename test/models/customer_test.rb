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

  private

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
