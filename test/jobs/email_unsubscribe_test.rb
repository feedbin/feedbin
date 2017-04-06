require 'test_helper'

class EmailUnsubscribeTest < ActiveSupport::TestCase

  test "should send unsubscribe message" do
    feed_options = {
      feed_type: :newsletter,
      options: {
        email_headers: {
          "List-Unsubscribe" => "<mailto:list-manager@host.com?body=unsubscribe%20list>"
        }
      }
    }
    feed = Feed.create(feed_options)
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      EmailUnsubscribe.new().perform(feed.id)
    end
  end

end
