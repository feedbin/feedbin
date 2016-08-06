require 'test_helper'

class UnreadEntriesControllerTest < ActionController::TestCase

  setup do
    flush_redis
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should toggle read" do
    login_as @user
    assert_difference "UnreadEntry.count", -1 do
      xhr :patch, :update, id: @entries.first
      assert_response :success
    end
    assert_difference "UnreadEntry.count", +1 do
      xhr :patch, :update, id: @entries.first
      assert_response :success
    end
  end

end
