require "test_helper"

class RecentlyReadEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    @user.recently_read_entries.create!(entry: @entries.first)
    login_as @user
    get :index, xhr: true
    assert_response :success
    assert assigns(:entries).present?
  end

  test "should destroy all recently read entries" do
    @entries.each do |entry|
      @user.recently_read_entries.create!(entry: entry)
    end
    login_as @user
    assert_difference("RecentlyReadEntry.count", -@entries.length) do
      delete :destroy_all, xhr: true
      assert_response :success
    end
  end
end
