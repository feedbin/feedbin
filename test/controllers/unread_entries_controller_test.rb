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

  test "should not toggle read on an entry the user cannot read" do
    entry = create_entry(feeds(:kottke))
    refute @user.can_read_entry?(entry.id), "precondition: user cannot read this entry"

    login_as @user
    assert_no_difference "UnreadEntry.count" do
      patch :update, params: {id: entry}, xhr: true
    end
    assert_response :not_found
  end
end
