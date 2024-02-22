require "test_helper"
class Api::Podcasts::V1::SubscriptionsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @user.podcast_subscriptions.first.subscribed!
  end

  test "should get index" do
    playlist = @user.playlists.create!(title: "Favorites")
    subscription = @user.podcast_subscriptions.first
    subscription.update!(playlist: playlist)

    login_as @user
    get :index, format: :json
    assert_response :success
    data = parse_json

    feed = subscription.feed
    assert_equal(subscription.id, data.first.safe_dig("id"))
    assert_equal(feed.id, data.first.safe_dig("feed_id"))
    assert_equal(playlist.id, data.first.safe_dig("playlist_id"))
    assert_nil(data.first.safe_dig("title"))
    assert_equal(feed.feed_url, data.first.safe_dig("feed_url"))
    assert_equal("subscribed", data.first.safe_dig("status"))
  end

  test "should create" do
    api_content_type
    login_as @user

    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("atom.xml", feed_url)

    playlist = @user.playlists.create!(title: "Favorites")

    assert_difference "PodcastSubscription.count", +1 do
      post :create, params: {feed_url: feed_url, status: "subscribed", playlist_id: playlist.id}, format: :json
      assert_response :created
    end

    data = parse_json
    assert_equal(feed_url, data.safe_dig("feed_url"))

    assert PodcastSubscription.last.reload.subscribed?, "Subscription should be subscribed"
  end

  test "should delete" do
    api_content_type
    login_as @user

    assert_difference "PodcastSubscription.count", -1 do
      post :destroy, params: {id: @user.subscriptions.first.feed_id}, format: :json
      assert_response :success
    end
  end

  test "should update" do
    api_content_type
    login_as @user

    subscription = @user.podcast_subscriptions.first

    playlist = @user.playlists.create!(title: "Favorites")
    entry = create_entry(subscription.feed)

    patch :update, params: {id: subscription.feed_id, status: "bookmarked", status_updated_at: Time.now.iso8601(6), playlist_id: playlist.id, playlist_id_updated_at: Time.now.iso8601(6), title: "Title", title_updated_at: Time.now.iso8601(6)}, format: :json
    assert_response :success

    assert subscription.reload.bookmarked?, "Subscription should be bookmarked"
    assert subscription.attribute_changes.present?
    assert_equal(playlist.id, @user.queued_entries.first.playlist_id)
    assert_equal(subscription.reload.title, "Title")
    changes = subscription.attribute_changes.pluck(:name).to_set
    assert_equal(["playlist_id", "status", "title"].to_set, changes)
  end

  test "should not update" do
    api_content_type
    login_as @user

    subscription = @user.podcast_subscriptions.first
    subscription.bookmarked!
    subscription.subscribed!

    playlist = @user.playlists.create!(title: "Favorites")

    patch :update, params: {id: subscription.feed_id, status: "bookmarked", status_updated_at: 10.seconds.ago.iso8601(6), playlist_id: playlist.id, playlist_id_updated_at: 10.seconds.ago.iso8601(6)}, format: :json
    assert_response :success

    assert_equal("subscribed", subscription.reload.status)
    assert_nil(subscription.reload.playlist)
  end
end
