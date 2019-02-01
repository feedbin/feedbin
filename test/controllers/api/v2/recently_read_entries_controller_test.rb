require "test_helper"

class Api::V2::RecentlyReadEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    recently_read = @entries.map { |entry|
      RecentlyReadEntry.create(user: @user, entry: entry)
    }

    login_as @user
    get :index, format: :json
    assert_response :success
    response = parse_json
    assert_equal(Set.new(@entries.map(&:id)), Set.new(response))
  end

  test "should create recently read entry" do
    api_content_type
    entry = @entries.sample

    login_as @user
    assert_difference "RecentlyReadEntry.count", +1 do
      post :create, params: {recently_read_entries: [entry.id]}, format: :json
      assert_response :success
    end
  end
end
