require 'test_helper'

class SubscriptionTest < ActiveSupport::TestCase

  test "should enqueue EmailUnsubscribe" do
    user = users(:ben)
    subscription = user.subscriptions.first
    assert_difference "EmailUnsubscribe.jobs.size", +1 do
      subscription.destroy
    end
  end


end
