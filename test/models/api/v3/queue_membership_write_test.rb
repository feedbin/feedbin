require "test_helper"

class Api::V3::QueueMembershipWriteTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    feed = create_feeds(@user, 1).first
    @entries = 3.times.map { create_entry(feed) }
    @rows = @entries.each_with_index.map do |entry, index|
      QueuedEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: feed.id, order: index)
    end
  end

  test "a bulk write reads every row's stamps in one query" do
    @rows.each { it.update!(progress: 1, order: it.order + 10) }
    stamp = 1.minute.from_now.utc.iso8601
    bodies = @entries.map do |entry|
      {"id" => entry.id, "progress_in_seconds" => 20, "progress_in_seconds_updated_at" => stamp, "sort_order" => 5, "sort_order_updated_at" => stamp, "playlist_id" => nil, "playlist_id_updated_at" => stamp}
    end

    reads = attribute_change_reads { Api::V3::QueueMembershipWrite.apply_all(@user, bodies) }

    assert_equal 1, reads
    assert_equal [[20, 5]] * 3, @rows.map { it.reload.values_at(:progress, :order) }
  end

  test "a bulk write still compares each field with its own stamp" do
    @rows.first.update!(progress: 100)
    before = (@rows.first.progress_updated_at - 1.minute).utc.iso8601
    after = 1.minute.from_now.utc.iso8601

    result = Api::V3::QueueMembershipWrite.apply_all(@user, [
      {"id" => @entries.first.id, "progress_in_seconds" => 50, "progress_in_seconds_updated_at" => before},
      {"id" => @entries.second.id, "progress_in_seconds" => 50, "progress_in_seconds_updated_at" => after}
    ])

    assert_equal({applied: [@entries.second.id], skipped: [{id: @entries.first.id, reason: "stale_write"}]}, result)
    assert_equal [100, 50], @rows.first(2).map { it.reload.progress }
  end

  test "a row sent twice is judged the second time against the first write" do
    travel_to 1.hour.from_now do
      earlier = 10.minutes.ago.utc.iso8601
      Api::V3::QueueMembershipWrite.apply_all(@user, [
        {"id" => @entries.first.id, "progress_in_seconds" => 70, "progress_in_seconds_updated_at" => Time.current.utc.iso8601},
        {"id" => @entries.first.id, "progress_in_seconds" => 30, "progress_in_seconds_updated_at" => earlier}
      ])
    end

    assert_equal 70, @rows.first.reload.progress
  end

  private

  def attribute_change_reads
    reads = 0
    counter = ->(*, payload) { reads += 1 if payload[:sql].match?(/\ASELECT.*FROM "attribute_changes"/m) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    reads
  end
end
