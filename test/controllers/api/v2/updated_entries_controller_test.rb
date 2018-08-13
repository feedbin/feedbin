require "test_helper"

class Api::V2::UpdatedEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @entries.map do |entry|
      UpdatedEntry.create_from_owners(@user.id, entry)
    end
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    results = parse_json
    assert_equal Set.new(@user.updated_entries.pluck(:entry_id)), Set.new(results)
  end

  test "should destroy updated entry" do
    login_as @user
    assert_difference "UpdatedEntry.count", -@entries.length do
      delete :destroy, params: {updated_entries: @entries.map(&:id)}, format: :json
      assert_response :success
    end
  end
end
