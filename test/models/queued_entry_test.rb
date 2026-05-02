require "test_helper"

class QueuedEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = create_feeds(@user, 1).first
    @entry = @feed.entries.first
    @playlist = @user.playlists.create!(title: "Mine")
  end

  test "creating increments the entry's queued_entries_count counter cache" do
    assert_difference -> { @entry.reload.queued_entries_count }, +1 do
      QueuedEntry.create!(user: @user, entry: @entry, feed: @feed, playlist: @playlist)
    end
  end

  test "destroying decrements the entry's counter cache" do
    queued = QueuedEntry.create!(user: @user, entry: @entry, feed: @feed, playlist: @playlist)

    assert_difference -> { @entry.reload.queued_entries_count }, -1 do
      queued.destroy!
    end
  end

  test "tracking progress creates an AttributeChange when progress changes" do
    queued = QueuedEntry.create!(user: @user, entry: @entry, feed: @feed, playlist: @playlist)

    assert_difference -> { queued.attribute_changes.where(name: "progress").count }, +1 do
      queued.update!(progress: 50)
    end
  end
end
