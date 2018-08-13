require "test_helper"

class CouponTest < ActiveSupport::TestCase
  test "should generate code" do
    user = users(:new)
    coupon = user.create_coupon!
    assert_not_nil coupon.coupon_code
  end
end
