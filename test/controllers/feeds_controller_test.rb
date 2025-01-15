require "test_helper"

class FeedsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "gets feed by url" do
    login_as @user
    stub_request_file("atom.xml", "http://example.com/")
    post :search, params: {q: "example.com"}, xhr: true
    assert_equal("Feedbin", assigns(:feeds).first.title)

    # should also update the feed when changed
    stub_request_file("atom_update.xml", "http://example.com/")
    post :search, params: {q: "example.com"}, xhr: true

    assert_equal("Custom Newsletter Addresses", assigns(:feeds).first.entries.order(published: :desc).first.title)
  end

  test "gets feed by search" do
    login_as @user
    clear_search
    @user = users(:new)
    @feeds = create_feeds(@user)
    Feed.update_all(subscriptions_count: 101)

    Search::ReindexFeeds.new.perform
    Search.client { _1.refresh }

    post :search, params: {q: @feeds.first.title}, xhr: true

    assert_equal(@feeds.first.title, assigns(:feeds).first.title)
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
