require "test_helper"

class Api::V2::EntryCountsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get post_frequency" do
    login_as @user
    get :post_frequency, format: :json
    assert_response :success
    assert_kind_of Array, parse_json
  end
end
