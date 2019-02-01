require "test_helper"

class Api::V2::StarredEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get starred entries" do
    starred = @entries.map { |entry|
      StarredEntry.create_from_owners(@user, entry)
    }
    login_as @user
    get :index, format: :json
    results = parse_json
    assert_equal Set.new(starred.map(&:entry_id)), Set.new(results)
  end

  test "should create starred entry" do
    api_content_type
    login_as @user
    entry = @entries.sample
    assert_difference "StarredEntry.count", +1 do
      post :create, params: {starred_entries: [entry.id]}, format: :json
      assert_response :success
    end
  end

  test "should destroy starred entry" do
    starred = @entries.sample(2).map { |entry|
      StarredEntry.create_from_owners(@user, entry)
    }
    login_as @user
    assert_difference "StarredEntry.count", -starred.count do
      delete :destroy, params: {starred_entries: starred.map(&:entry_id)}, format: :json
      assert_response :success
    end
  end
end
