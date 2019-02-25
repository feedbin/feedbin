require "test_helper"

class Api::V2::UnreadEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    results = parse_json
    assert_equal Set.new(@user.unread_entries.pluck(:entry_id)), Set.new(results)
  end

  test "should create unread entry" do
    UnreadEntry.delete_all
    api_content_type
    login_as @user
    entries = @entries.sample(2)
    assert_difference "UnreadEntry.count", +entries.length do
      post :create, params: {unread_entries: entries.map(&:id)}, format: :json
      assert_response :success
    end
  end

  test "should destroy unread entry" do
    api_content_type
    login_as @user
    entries = @entries.sample(2)
    assert_difference "UnreadEntry.count", -entries.length do
      delete :destroy, params: {unread_entries: entries.map(&:id)}, format: :json
      assert_response :success
    end
  end
end
