require "test_helper"

class TrialExpirationTest < ActiveSupport::TestCase
  test "should deactivate users" do
    create_stripe_price(plans(:trial))
    user = users(:ann)
    user.expires_at = Time.now
    user.save(validate: false)

    assert_not user.suspended
    TrialExpiration.new.perform
    assert user.reload.suspended
  end

  test "should deactivate timed users" do
    create_stripe_price(plans(:timed))
    user = users(:timed)
    user.expires_at = Time.now
    user.save(validate: false)

    assert_not user.suspended
    Sidekiq::Testing.inline! do
      assert_difference -> { ActionMailer::Base.deliveries.count }, +1 do
        TrialExpiration.new.perform
      end
    end
    assert user.reload.suspended
  end

  test "should not deactivate timed users with time remaining" do
    create_stripe_price(plans(:timed))
    user = users(:timed)
    user.expires_at = Time.now + 5.seconds
    user.save(validate: false)

    assert_not user.suspended
    TrialExpiration.new.perform
    assert_not user.reload.suspended
  end
end
