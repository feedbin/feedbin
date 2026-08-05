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

  test "find_or_create_by recovers the row a concurrent request inserted first" do
    # The same account playing an episode on two devices: both requests find
    # nothing, and the second one's INSERT is the one the unique index rejects.
    # The winner is committed from a real second connection, so it survives the
    # savepoint the losing INSERT rolls back.
    @committed = [@user.id, @entry.id]
    owners = @committed

    outside_transaction do |other_request|
      raced = false
      race_winner = ->(_record) do
        next if raced
        raced = true
        other_request.execute(<<~SQL, *owners)
          INSERT INTO recently_played_entries (user_id, entry_id, created_at, updated_at)
          VALUES (?, ?, now(), now())
        SQL
      end
      RecentlyPlayedEntry.set_callback(:create, :before, race_winner)

      begin
        recent = nil
        assert_difference -> { RecentlyPlayedEntry.count }, +1 do
          recent = @user.recently_played_entries.find_or_create_by(entry_id: @entry.id)
        end
        assert raced, "the race was never triggered"
        assert recent.persisted?, "should come back with the row the other request wrote"
      ensure
        RecentlyPlayedEntry.skip_callback(:create, :before, race_winner)
      end
    end
  end

  # Runs after the fixture transaction has rolled back, so the DELETE does not
  # wait on rows this test left uncommitted.
  def after_teardown
    super
    return unless @committed
    outside_transaction do |connection|
      connection.execute("DELETE FROM recently_played_entries WHERE user_id = ? AND entry_id = ?", *@committed)
    end
  end
end
