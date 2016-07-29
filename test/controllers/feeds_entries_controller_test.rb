require 'test_helper'

class FeedsEntriesControllerTest < ActionController::TestCase

  test "gets the index" do
    flush_redis
    user = users(:new)
    feeds = create_feeds(user)
    entries = user.entries

    login_as user

    xhr :get, :index, feed_id: feeds.first
    assert_response :success
    assert_equal feeds.first.entries.length, assigns(:entries).length
  end

end
