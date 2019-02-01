require "test_helper"

class EmailsControllerTest < ActionController::TestCase
  test "should create subscription" do
    user = users(:ann)
    feed = Feed.create(feed_url: "http://example.com")
    assert_difference("Subscription.count") do
      post :create, params: {
        TextBody: feed.feed_url,
        MailboxHash: user.inbound_email_token,
      }
    end
    assert_response :success
  end
end
