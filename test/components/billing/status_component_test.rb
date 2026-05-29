require "test_helper"

class Billing::StatusComponentTest < ComponentTestCase
  test "default plan renders payment info, change-plan options, and the billing_details hook" do
    user = users(:ben)
    plans = user.available_plans
    other_plan = plans.detect { |plan| plan.id != user.plan.id }

    # The default branch renders the payment_history/receipt_info ERB partials,
    # which read these controller-provided ivars. Assign on the controller so
    # they propagate into the view context used for partial rendering.
    controller.instance_variable_set(:@user, user)
    controller.instance_variable_set(:@billing_events, [])
    controller.instance_variable_set(:@next_payment_date, nil)

    html = render(Billing::StatusComponent.new(user: user, plans: plans, default_plan: plans.first)).to_s

    assert_includes html, 'data-behavior="billing_details"'
    assert_includes html, "Change Your Plan"
    assert_includes html, "Plan changes are pro-rated."
    assert_includes html, "Payment Information"

    if other_plan
      assert_includes html, "Switch to this plan"
      assert_includes html, %(value="#{other_plan.id}")
      assert_includes html, "authenticity_token"
      assert_includes html, "Are you sure you want to switch to #{other_plan.name.downcase} billing?"
    end
  end

  test "free plan renders Free for life" do
    user = users(:ben)
    free_plan = Plan.find_by(stripe_id: "free")
    user.plan = free_plan

    html = render(Billing::StatusComponent.new(user: user, plans: user.available_plans, default_plan: nil)).to_s

    assert_includes html, "Your Plan"
    assert_includes html, "Free for life"
  end
end
