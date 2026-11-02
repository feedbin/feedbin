require "test_helper"

class SyncVersionTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @entries = 3.times.map { |i| @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex) }
  end

  test "every list starts at zero" do
    assert_equal({"unread" => 0, "starred" => 0, "subscriptions" => 0}, SyncVersion.for(@user))
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
