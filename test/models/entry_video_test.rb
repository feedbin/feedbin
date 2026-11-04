require "test_helper"

class EntryVideoTest < ActiveSupport::TestCase
  setup do
    @feed = Feed.create!(feed_url: "https://example.com/feed")
    @entry = create_entry(@feed)
    @other = create_entry(@feed)
  end

  test "record keeps one row per entry and video" do
    assert_equal %w[a b], EntryVideo.record(entry_id: @entry.id, provider_ids: %w[a b]).sort
    assert_equal %w[c], EntryVideo.record(entry_id: @entry.id, provider_ids: %w[b c])

    assert_equal %w[a b c], EntryVideo.where(entry_id: @entry.id).order(:provider_id).pluck(:provider_id)
  end

  test "record with no ids writes nothing" do
    assert_no_difference "EntryVideo.count" do
      EntryVideo.record(entry_id: @entry.id, provider_ids: [])
    end
  end

  test "bump_for_videos marks mapped entries edited" do
    EntryVideo.record(entry_id: @entry.id, provider_ids: %w[a])

    assert_equal 1, EntryVideo.bump_for_videos(%w[a])

    @entry.reload
    assert_equal 2, @entry.revision
    assert_not_nil @entry.edited_at
    assert_equal 1, @other.reload.revision
    assert_nil @other.edited_at
  end

  test "an entry mapped to several bumped videos is bumped once" do
    EntryVideo.record(entry_id: @entry.id, provider_ids: %w[a b])

    EntryVideo.bump_for_videos(%w[a b])

    assert_equal 2, @entry.reload.revision
  end

  test "bump_for_channel marks entries mapped to that channel's videos" do
    Embed.create!(source: :youtube_video, provider_id: "a", parent_id: "UC1", data: {})
    Embed.create!(source: :youtube_video, provider_id: "b", parent_id: "UC2", data: {})
    EntryVideo.record(entry_id: @entry.id, provider_ids: %w[a])
    EntryVideo.record(entry_id: @other.id, provider_ids: %w[b])

    assert_equal 1, EntryVideo.bump_for_channel("UC1")

    assert_equal 2, @entry.reload.revision
    assert_equal 1, @other.reload.revision
  end

  test "a bump with nothing to bump changes no entry" do
    EntryVideo.record(entry_id: @entry.id, provider_ids: %w[a])
    Embed.create!(source: :youtube_video, provider_id: "a", parent_id: nil, data: {})

    assert_equal 0, EntryVideo.bump_for_videos([])
    assert_equal 0, EntryVideo.bump_for_channel(nil)
    assert_equal 0, EntryVideo.bump_for_channel("")

    assert_equal 1, @entry.reload.revision
  end

  test "deleting the entry deletes its rows" do
    EntryVideo.record(entry_id: @entry.id, provider_ids: %w[a])

    assert_difference "EntryVideo.count", -1 do
      @entry.destroy
    end
  end
end
