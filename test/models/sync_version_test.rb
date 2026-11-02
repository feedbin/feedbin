require "test_helper"

class SyncVersionTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @entries = 3.times.map { |i| @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex) }
  end

  test "every list starts at zero" do
    assert_equal SyncVersion::LISTS.index_with(0), SyncVersion.for(@user)
    assert_equal %w[unread starred subscriptions updated recently_read recently_played queue saved_searches playlists actions], SyncVersion::LISTS
  end

  test "the other per-user lists bump their own versions" do
    entry = @entries.first
    UpdatedEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: @feed.id, published: entry.published, updated: Time.now)
    @user.updated_entries.delete_all
    assert_equal 2, SyncVersion.for(@user)["updated"]

    RecentlyReadEntry.create_from_owners(@user, entry.id)
    assert_equal 1, SyncVersion.for(@user)["recently_read"]

    RecentlyPlayedEntry.create!(user_id: @user.id, entry_id: entry.id, progress: 10, duration: 100)
    assert_equal 1, SyncVersion.for(@user)["recently_played"]

    queued = QueuedEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: @feed.id)
    queued.update!(progress: 5)
    queued.destroy
    assert_equal 3, SyncVersion.for(@user)["queue"]

    search = @user.saved_searches.create!(name: "Swift", query: "swift")
    search.update!(name: "Swift!")
    search.destroy
    assert_equal 3, SyncVersion.for(@user)["saved_searches"]

    playlist = @user.playlists.create!(title: "Commute")
    playlist.update!(sort_order: :newest_first)
    playlist.destroy
    assert_equal 3, SyncVersion.for(@user)["playlists"]
  end

  test "actions bump their version" do
    @user.subscriptions.create!(feed: @feed)
    action = @user.actions.new(title: "Star", query: "", feed_ids: [@feed.id.to_s], actions: ["star"], automatic_modification: true)
    action.save!
    action.update!(title: "Star!")
    action.destroy
    assert_equal 3, SyncVersion.for(@user)["actions"]
  end

  test "an unread insert and a bulk delete each bump unread once" do
    UnreadEntry.import(@entries.map { UnreadEntry.new_from_owners(@user, _1) }, validate: false)
    assert_equal 1, SyncVersion.for(@user)["unread"]
    @user.unread_entries.delete_all
    assert_equal 2, SyncVersion.for(@user)["unread"]
  end

  test "an import that inserts nothing does not bump" do
    rows = @entries.map { UnreadEntry.new_from_owners(@user, _1) }
    UnreadEntry.import(rows, validate: false, on_duplicate_key_ignore: true)
    UnreadEntry.import(rows, validate: false, on_duplicate_key_ignore: true)
    assert_equal 1, SyncVersion.for(@user)["unread"]
  end

  test "starred rows bump starred" do
    StarredEntry.create_from_owners(@user, @entries.first)
    @user.starred_entries.destroy_all
    assert_equal 2, SyncVersion.for(@user)["starred"]
  end

  test "subscription inserts, updates, deletes and taggings bump subscriptions" do
    subscription = @user.subscriptions.create!(feed: @feed)
    subscription.update!(title: "Custom")
    @feed.tag("Apple", @user)
    # destroy untags first, so the tagging delete and the row delete are two bumps
    subscription.destroy
    assert_equal 5, SyncVersion.for(@user)["subscriptions"]
  end

  test "renaming a tag bumps subscriptions" do
    @user.subscriptions.create!(feed: @feed)
    tag = @feed.tag("Apple", @user).first.tag
    before = SyncVersion.for(@user)["subscriptions"]

    Tag.rename(@user, tag, "Fruit")

    assert_equal before + 1, SyncVersion.for(@user)["subscriptions"]
  end

  test "other users' rows do not bump this user" do
    UnreadEntry.create_from_owners(users(:ben), @entries.first)
    assert_equal 0, SyncVersion.for(@user)["unread"]
  end
end
