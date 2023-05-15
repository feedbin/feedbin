require "test_helper"
class Api::Podcasts::V1::QueuedEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @subscription = @user.podcast_subscriptions.first
    @feed = @subscription.feed
    @entry = create_entry(@feed)
    @queued_entry = @user.queued_entries.first
  end

  test "should get index" do
    login_as @user
    playlist = @user.playlists.create!(title: "Favorites")
    @queued_entry.update!(playlist: playlist)
    get :index, format: :json
    assert_response :success
    data = parse_json
    assert_equal(@entry.id, data.first.safe_dig("entry_id"))
    assert_equal(@entry.feed.id, data.first.safe_dig("feed_id"))
    assert_equal(playlist.id, data.first.safe_dig("playlist_id"))
    assert_not_nil data.first.safe_dig("id")
    assert_not_nil data.first.safe_dig("order")
    assert_not_nil data.first.safe_dig("progress")
    assert_not_nil data.first.safe_dig("created_at")
    assert_not_nil data.first.safe_dig("updated_at")
  end

  test "should create" do
    api_content_type
    login_as @user
    @user.queued_entries.delete_all
    assert_difference "QueuedEntry.count", +1 do
      post :create, params: {entry_id: @entry.id, progress: 10, order: 10}, format: :json
      assert_response :success
    end
  end

  test "should delete" do
    api_content_type
    login_as @user

    assert_difference "QueuedEntry.count", -1 do
      post :destroy, params: {id: @queued_entry.entry_id}, format: :json
      assert_response :success
    end
  end

  test "should update" do
    api_content_type
    login_as @user

    progress = 10

    playlist = @user.playlists.create!(title: "Favorites")

    patch :update, params: {id: @queued_entry.entry_id, progress: progress, progress_updated_at: Time.now.iso8601(6), playlist_id: playlist.id, playlist_id_updated_at: Time.now.iso8601(6)}, format: :json
    assert_response :success

    assert @queued_entry.reload.progress, progress
    assert @queued_entry.reload.playlist, playlist
    assert_equal("progress", @queued_entry.attribute_changes.first.name)
  end

  test "should not update" do

    api_content_type
    login_as @user

    progress = 10

    playlist = @user.playlists.create!(title: "Favorites")

    patch :update, params: {id: @queued_entry.entry_id, progress: progress, progress_updated_at: 1.second.ago.iso8601(6), playlist_id: playlist.id, playlist_id_updated_at: 1.second.ago.iso8601(6)}, format: :json
    assert_response :success

    assert_equal 0, @queued_entry.reload.progress
    assert_nil(@queued_entry.reload.playlist)

  end

end
