require "test_helper"

class TrialSendExpirationTest < ActiveSupport::TestCase
  test "should send expiration notice" do
    user = users(:ann)
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      TrialSendExpiration.new.perform(user.id)
    end
  end
end
