require "test_helper"

class QueuedEntriesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entry = @user.entries.first
    @playlist = @user.playlists.create!(title: "Mine")
    QueuedEntry.create!(user: @user, entry: @entry, feed: @entry.feed, playlist: @playlist)
  end

  test "index returns the user's queued entries" do
    login_as @user

    get :index, xhr: true
    assert_response :success
    assert_equal [@entry], assigns(:entries)
    assert_equal "queued_entries", assigns(:type)
    assert_equal "Queued Entries", assigns(:collection_title)
  end
end
