require "test_helper"

class UpdatedEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @updated = @entries.each do |entry|
      UpdatedEntry.create_from_owners(@user.id, entry)
    end
  end

  test "should get index" do
    login_as @user
    get :index, xhr: true
    assert_response :success
    assert_equal @updated.length, assigns(:entries).length
  end
end
