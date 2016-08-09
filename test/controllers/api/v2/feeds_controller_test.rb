require 'test_helper'

class Api::V2::FeedsControllerTest < ApiControllerTestCase

  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
  end

  test "should show feed" do
    login_as @user
    feed = @feeds.first

    get :show, id: feed, format: :json
    assert_response :success

    feed = parse_json
    assert_has_keys(feed_keys, feed)
  end

  private

  def feed_keys
    %w[id title feed_url site_url]
  end
end
