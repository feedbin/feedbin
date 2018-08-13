require "test_helper"

class UnreadEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should toggle read" do
    login_as @user
    assert_difference "UnreadEntry.count", -1 do
      patch :update, params: {id: @entries.first}, xhr: true
      assert_response :success
    end
    assert_difference "UnreadEntry.count", +1 do
      patch :update, params: {id: @entries.first}, xhr: true
      assert_response :success
    end
  end
end
