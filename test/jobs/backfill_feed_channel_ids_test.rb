require "test_helper"

class BackfillFeedChannelIdsTest < ActiveSupport::TestCase
  # update_column, not update: channel_id is in no view, and bumping
  # updated_at on every YouTube feed at once would invalidate the sidebar and
  # every entry list referencing them for a change nobody can see.
  test "populates channel_id without moving updated_at" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCbackfill")
    feed.update_columns(channel_id: nil, updated_at: 1.year.ago)
    before = feed.reload.updated_at

    BackfillFeedChannelIds.new.perform

    feed.reload
    assert_equal "UCbackfill", feed.channel_id
    assert_equal before.to_f, feed.updated_at.to_f
  end

  test "populates channel_id from the parsed options too" do
    feed = Feed.create!(feed_url: "http://example.com/videos.xml", options: {"youtube_channel_id" => "UCparsed"})
    feed.update_column(:channel_id, nil)

    BackfillFeedChannelIds.new.perform

    assert_equal "UCparsed", feed.reload.channel_id
  end

  test "leaves feeds that are not youtube alone" do
    feed = create_feeds(users(:ben)).first

    BackfillFeedChannelIds.new.perform

    assert_nil feed.reload.channel_id
  end
end
