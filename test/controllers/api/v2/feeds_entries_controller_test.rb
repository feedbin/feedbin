require "test_helper"

class Api::V2::FeedsEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    login_as @user
    feed = @feeds.first
    get :index, params: {feed_id: feed}, format: :json
    assert_equal_ids(feed.entries, parse_json)
  end

  test "should show entry" do
    login_as @user
    entry = @entries.sample
    get :show, params: {feed_id: entry.feed_id, id: entry}, format: :json
    assert_response :success
  end
end
