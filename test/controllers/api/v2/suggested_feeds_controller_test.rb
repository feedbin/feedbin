require "test_helper"

class Api::V2::SuggestedFeedsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @category = SuggestedCategory.create!(name: "Popular")
    @feed = Feed.create(feed_url: Faker::Internet.url)
    @suggested_feed = SuggestedFeed.create!(suggested_category: @category, feed: @feed)
  end

  test "gets index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    results = parse_json
    assert_has_keys keys, results.first
  end

  test "should subscribe to suggested feed" do
    login_as @user

    assert_difference "Subscription.count", +1 do
      post :subscribe, params: {id: @suggested_feed}, format: :json
      assert_response :success
    end
  end

  test "should unsubscribe from suggested feed" do
    @user.subscriptions.create(feed: @feed)
    login_as @user

    assert_difference "Subscription.count", -1 do
      delete :unsubscribe, params: {id: @suggested_feed}, format: :json
      assert_response :success
    end
  end

  private

  def keys
    %w[id feed_id suggested_category_id title host]
  end
end
