require "test_helper"

class FeedsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "update feed" do
    login_as @user

    assert_difference("Tagging.count", 2) do
      patch :update, params: {id: @user.feeds.first, tag_id: {"1" => "Tag"}, tag_name: ["Tag 2"]}, xhr: true
      assert_response :success
    end
  end

  test "rename feed" do
    login_as @user
    feed = @user.feeds.first
    title = Faker::Lorem.sentence
    patch :rename, params: {feed_id: feed, feed: {title: title}}, xhr: true
    assert @user.subscriptions.where(title: title, feed: feed).length == 1
  end

  test "gets auto_update" do
    login_as @user
    get :auto_update, xhr: true
    assert_response :success
  end
end
