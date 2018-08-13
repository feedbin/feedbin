require "test_helper"

class TrialExpirationTest < ActiveSupport::TestCase
  test "should deactivate users" do
    StripeMock.start
    create_stripe_plan(plans(:trial))
    user = users(:ann)
    user.created_at = Feedbin::Application.config.trial_days.days.ago
    user.save(validate: false)

    assert_not user.suspended
    TrialExpiration.new().perform
    assert user.reload.suspended
    StripeMock.stop
  end
end
