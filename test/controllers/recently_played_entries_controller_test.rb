require "test_helper"

class RecentlyPlayedEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get index" do
    @user.recently_played_entries.create!(entry: @entries.first)
    login_as @user
    get :index, xhr: true
    assert_response :success
    assert assigns(:entries).present?
  end

  test "should create recently played" do
    login_as @user

    entry = @entries.first

    params = {
      entry_id: entry.id,
      progress: 7,
      duration: 8,
    }

    assert_difference("RecentlyPlayedEntry.count") do
      post :create, params: {id: entry.id, recently_played_entry: params}, xhr: true
    end
  end
end
