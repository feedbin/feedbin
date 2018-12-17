require "test_helper"

class FeedsEntriesControllerTest < ActionController::TestCase
  test "gets the index" do
    user = users(:new)
    feeds = create_feeds(user)
    entries = user.entries

    login_as user

    get :index, params: {feed_id: feeds.first}, xhr: true
    assert_response :success
    assert_equal feeds.first.entries.length, assigns(:entries).length
  end
end
