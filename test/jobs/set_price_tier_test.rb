require 'test_helper'

class SetPriceTierTest < ActiveSupport::TestCase
  test "should set price tier" do
    user = users(:ben)
    user.update(price_tier: nil)
    assert_nil(user.reload.price_tier)
    SetPriceTier.new().perform(user.id)
    assert_equal(user.plan.price_tier, user.reload.price_tier)
  end
end
