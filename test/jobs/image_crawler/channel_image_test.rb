require "test_helper"

module ImageCrawler
  class ChannelImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    def channel(thumbnails)
      Embed.youtube_channel.create!(
        provider_id: "UCabc",
        data: {"snippet" => {"thumbnails" => thumbnails}}
      )
    end

    # The channels API returns default (88x88), medium (240x240) and high
    # (800x800); take the largest.
    test "schedules a Find job for the largest thumbnail" do
      record = channel({
        "default" => {"url" => "https://yt3.ggpht.com/small.jpg"},
        "medium"  => {"url" => "https://yt3.ggpht.com/medium.jpg"},
        "high"    => {"url" => "https://yt3.ggpht.com/large.jpg"}
      })

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ChannelImage.schedule(record)
      end

      args = Pipeline::Find.jobs.last["args"].first
      assert_equal ["https://yt3.ggpht.com/large.jpg"], args["image_urls"]
      assert_equal "channel_avatar", args["preset_name"]
      assert_equal ::Image.providers[:embed_icon], args["provider"]
      assert_equal "UCabc", args["provider_id"]
      assert_equal "UCabc-channel", args["id"]
      assert_nil args["feed_id"], "the row belongs to the channel, not to any one feed"
    end

    test "falls back down the thumbnail ladder" do
      ChannelImage.schedule(channel({"default" => {"url" => "https://yt3.ggpht.com/small.jpg"}}))

      assert_equal ["https://yt3.ggpht.com/small.jpg"],
        Pipeline::Find.jobs.last["args"].first["image_urls"]
    end

    test "schedules nothing when the channel advertises no thumbnail" do
      record = Embed.youtube_channel.create!(provider_id: "UCabc", data: {})

      assert_no_difference -> { Pipeline::Find.jobs.size } do
        ChannelImage.schedule(record)
      end
    end

    # The sidebar's key and entries_cache_key both include the feed, not the
    # icon row, so a feed rendering this channel has to be touched or it keeps
    # serving the old avatar.
    test "touches every feed for the channel when the avatar was stored" do
      one = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      two = Feed.create!(feed_url: "https://youtube.com/feeds/videos.xml?channel_id=UCabc")
      [one, two].each { it.update_column(:updated_at, 1.year.ago) }
      before = one.reload.updated_at

      ChannelImage.new.perform("UCabc-channel", {"storage_path" => "abc/abc123.png", "provider_id" => "UCabc"})

      assert_operator one.reload.updated_at, :>, before
      assert_operator two.reload.updated_at, :>, before
    end

    # Channel ids are base64url ("-" is an ordinary character), so the
    # channel must come from provider_id, never parsed from the display id.
    test "keys on the payload's channel id, not a parse of the job id" do
      channel_id = "UC-lHJZR3Gqxm24_Vd_AJ5Yw"
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}")
      feed.update_column(:updated_at, 1.year.ago)
      before = feed.reload.updated_at

      ChannelImage.new.perform("#{channel_id}-channel", {"storage_path" => "abc/abc123.png", "provider_id" => channel_id})

      assert_operator feed.reload.updated_at, :>, before
    end

    # A payload written by a deploy predating provider_id must not fall
    # through to Feed.where(channel_id: nil), which matches every
    # non-YouTube feed in the table.
    test "touches nothing when the payload carries no provider_id" do
      stamp = 1.year.ago
      youtube = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      plain = Feed.create!(feed_url: "http://example.com/feed.xml")
      [youtube, plain].each { it.update_column(:updated_at, stamp) }

      ChannelImage.new.perform("UCabc-channel", {"storage_path" => "abc/abc123.png"})

      assert_equal stamp.to_f, plain.reload.updated_at.to_f
      assert_equal stamp.to_f, youtube.reload.updated_at.to_f
    end

    # storage_path is absent when the unified write failed and Upload degraded to
    # legacy -- and this preset has no legacy object. Nothing was stored, so
    # there is nothing to invalidate.
    test "touches nothing when nothing was stored" do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      feed.update_column(:updated_at, 1.year.ago)
      before = feed.reload.updated_at

      ChannelImage.new.perform("UCabc-channel", {"processed_url" => "https://cdn.example.com/a.png"})

      assert_equal before.to_f, feed.reload.updated_at.to_f
    end
  end
end
