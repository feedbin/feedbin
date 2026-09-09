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

  # Rows written while derived_channel_id trusted the channel feed's bare
  # yt:channelId hold the 22-character suffix without its UC prefix, so they
  # match no images row. The nil-only scope would skip them.
  test "repairs a bare channel_id an earlier crawl stored" do
    feed = Feed.create!(feed_url: "http://example.com/videos.xml", options: {"youtube_channel_id" => "BJycsmduvYEL83R_U4JriQ"})
    feed.update_columns(channel_id: "BJycsmduvYEL83R_U4JriQ", updated_at: 1.year.ago)
    before = feed.reload.updated_at

    BackfillFeedChannelIds.new.perform

    feed.reload
    assert_equal "UCBJycsmduvYEL83R_U4JriQ", feed.channel_id
    assert_equal before.to_f, feed.updated_at.to_f
  end

  # ChannelImage's touch fired against the wrong key and is not coming
  # again, so connecting a feed to an existing avatar must touch it here.
  test "touches the feed when the repair connects it to an existing avatar" do
    feed = Feed.create!(feed_url: "http://example.com/videos.xml", options: {"youtube_channel_id" => "BJycsmduvYEL83R_U4JriQ"})
    feed.update_columns(channel_id: "BJycsmduvYEL83R_U4JriQ", updated_at: 1.year.ago)
    Image.create!(
      provider: :embed_icon, provider_id: "UCBJycsmduvYEL83R_U4JriQ",
      url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )
    before = feed.reload.updated_at

    BackfillFeedChannelIds.new.perform

    feed.reload
    assert_equal "UCBJycsmduvYEL83R_U4JriQ", feed.channel_id
    assert_operator feed.updated_at, :>, before,
      "connecting the feed to an avatar it can now render must move its cache key"
  end

  test "leaves feeds that are not youtube alone" do
    feed = create_feeds(users(:ben)).first

    BackfillFeedChannelIds.new.perform

    assert_nil feed.reload.channel_id
  end
end
