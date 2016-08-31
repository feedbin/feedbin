require 'test_helper'

class CouponTest < ActiveSupport::TestCase
  test "should generate code" do
    coupon = Coupon.create
    assert_not_nil coupon.coupon_code
  end
end
