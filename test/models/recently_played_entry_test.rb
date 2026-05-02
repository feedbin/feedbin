require "test_helper"

class RecentlyPlayedEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = create_feeds(@user, 1).first
    @entry = @feed.entries.first
  end

  test "creating increments the entry's recently_played_entries_count counter cache" do
    assert_difference -> { @entry.reload.recently_played_entries_count }, +1 do
      RecentlyPlayedEntry.create!(user: @user, entry: @entry)
    end
  end

  test "destroying decrements the entry's counter cache" do
    played = RecentlyPlayedEntry.create!(user: @user, entry: @entry)

    assert_difference -> { @entry.reload.recently_played_entries_count }, -1 do
      played.destroy!
    end
  end
end
