require 'test_helper'

class EntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get thread" do
    login_as @user
    get :index, params: {id: @entries.first}, xhr: true
    assert_response :success
  end

end
