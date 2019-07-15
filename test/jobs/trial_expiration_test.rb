require "test_helper"

class TrialExpirationTest < ActiveSupport::TestCase
  test "should deactivate users" do
    StripeMock.start
    create_stripe_plan(plans(:trial))
    user = users(:ann)
    user.expires_at = Time.now
    user.save(validate: false)

    assert_not user.suspended
    TrialExpiration.new.perform
    assert user.reload.suspended
    StripeMock.stop
  end

  # test "should deactivate timed users" do
  #   StripeMock.start
  #   create_stripe_plan(plans(:timed))
  #   user = users(:timed)
  #   user.expires_at = Time.now
  #   user.save(validate: false)
  #
  #   assert_not user.suspended
  #   assert_difference -> { Sidekiq::Extensions::DelayedMailer.jobs.size }, +1 do
  #     TrialExpiration.new.perform
  #   end
  #   assert user.reload.suspended
  #
  #   StripeMock.stop
  # end
  #
  # test "should not deactivate timed users with time remaining" do
  #   StripeMock.start
  #   create_stripe_plan(plans(:timed))
  #   user = users(:timed)
  #   user.expires_at = Time.now + 5.seconds
  #   user.save(validate: false)
  #
  #   assert_not user.suspended
  #   TrialExpiration.new.perform
  #   assert_not user.reload.suspended
  #   StripeMock.stop
  # end
end
