require "test_helper"

class Api::V2::FeedsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
  end

  test "should show feed" do
    login_as @user
    feed = @feeds.first

    get :show, params: {id: feed}, format: :json
    assert_response :success

    feed = parse_json
    assert_has_keys(feed_keys, feed)
  end

  test "should not show feed that user is not subscribed to" do
    login_as @user
    feed = @feeds.first

    @user.subscriptions.destroy_all

    get :show, params: {id: feed}, format: :json
    assert_response :not_found
  end

  test "should show feed that user is not subscribed to but has starred entry" do
    login_as @user
    feed = @feeds.first
    entry = feed.entries.first
    StarredEntry.create_from_owners(@user, entry)

    @user.subscriptions.destroy_all

    get :show, params: {id: feed}, format: :json
    assert_response :success
  end

  private

  def feed_keys
    %w[id title feed_url site_url]
  end
end
