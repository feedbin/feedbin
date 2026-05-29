require "test_helper"

class Billing::SubscribeDescriptionComponentTest < ComponentTestCase
  test "immediate charge wording when the trial has passed" do
    user = users(:ben)
    user.stub(:trial_end, 1.day.ago) do
      plans = [plans(:basic_monthly_3), plans(:basic_yearly_3)]
      html = render(Billing::SubscribeDescriptionComponent.new(user: user, plans: plans, default_plan: plans.first)).to_s
      assert_includes html, "charge your card"
      assert_includes html, "immediately and again each month thereafter"
      assert_includes html, "again each year thereafter"
      assert_includes html, 'data-billing-target="planHelp"'
      # default (first) visible, the other hidden
      assert_includes html, "Full refunds are available at any time, no questions asked."
    end
  end

  test "the container is hidden and targeted so it only shows once the element mounts" do
    user = users(:ben)
    plans = [plans(:basic_yearly_3)]
    html = render(Billing::SubscribeDescriptionComponent.new(user: user, plans: plans, default_plan: plans.first)).to_s
    assert_includes html, 'data-billing-target="description"'
    assert_match(/<div class="subscribe-description[^"]*\bhidden\b/, html)
  end

  test "future-trial wording names the trial end date" do
    user = users(:ben)
    user.stub(:trial_end, 10.days.from_now) do
      plans = [plans(:basic_yearly_3)]
      html = render(Billing::SubscribeDescriptionComponent.new(user: user, plans: plans, default_plan: plans.first)).to_s
      assert_includes html, "when your trial ends on"
      assert_includes html, "again each year thereafter"
    end
  end
end
