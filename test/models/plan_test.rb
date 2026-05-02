require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "period strips the 'ly' suffix and downcases" do
    plan = Plan.new(name: "Monthly")
    assert_equal "month", plan.period

    plan = Plan.new(name: "Yearly")
    assert_equal "year", plan.period
  end

  test "price_in_cents converts price to integer cents" do
    plan = Plan.new(price: 5)
    assert_equal 500, plan.price_in_cents
  end

  test "price_in_cents truncates fractional dollars" do
    plan = Plan.new(price: 5.99)
    assert_equal 500, plan.price_in_cents
  end

  test "restricted? is true for the podcast subscription plan" do
    assert_predicate plans(:podcast_subscription), :restricted?
  end

  test "restricted? is false for ordinary plans" do
    refute_predicate plans(:basic_monthly_3), :restricted?
    refute_predicate plans(:trial), :restricted?
  end
end
