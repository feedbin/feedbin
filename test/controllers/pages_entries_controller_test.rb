require "test_helper"

class PagesEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = Feed.create!(feed_url: "https://pages.example/x", host: "pages.example", title: "P", feed_type: :pages)
    @user.subscriptions.create!(feed: @feed)
    @entry = @feed.entries.create!(content: "<p>x</p>", title: "T", url: "/x", public_id: SecureRandom.hex)
  end

  test "GET index requires login" do
    get :index, params: {id: @feed.id}
    assert_redirected_to login_url
  end

  test "GET index defaults to the unread view" do
    login_as @user
    get :index, params: {id: @feed.id}, xhr: true
    assert_response :success
    assert_equal "true", assigns(:all_unread)
  end

  test "GET index with view=view_all takes the all-entries branch" do
    login_as @user
    get :index, params: {id: @feed.id, view: "view_all"}, xhr: true
    assert_response :success
    refute assigns(:all_unread)
  end

  test "GET index with view=view_starred takes the starred branch" do
    login_as @user
    @user.starred_entries.create!(entry_id: @entry.id, feed_id: @feed.id)
    get :index, params: {id: @feed.id, view: "view_starred"}, xhr: true
    assert_response :success
    refute assigns(:all_unread)
  end
end
