require "test_helper"

module ImageCrawler
  class ItunesFeedImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @feed = Feed.first
      @feed.update(host: "example.com")
    end

    test "schedules a Find job when the feed has an itunes_image option" do
      @feed.update!(options: {"itunes_image" => "http://example.com/cover.jpg"})

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ItunesFeedImage.new.perform(@feed.id)
      end

      args = Pipeline::Find.jobs.last["args"].first
      name = Digest::SHA1.hexdigest("http://example.com/cover.jpg")
      assert_equal "#{@feed.id}-#{name}-itunes", args["id"]
      assert_equal "podcast_feed", args["preset_name"]
      assert_equal ["http://example.com/cover.jpg"], args["image_urls"]
    end

    test "schedules nothing when the feed has no itunes_image option" do
      @feed.update!(options: {})

      assert_no_difference -> { Pipeline::Find.jobs.size } do
        ItunesFeedImage.new.perform(@feed.id)
      end
    end

    test "accepts a feed_id with a trailing -suffix" do
      @feed.update!(options: {"itunes_image" => "http://example.com/cover.jpg"})
      suffixed_id = "#{@feed.id}-#{Digest::SHA1.hexdigest("http://example.com/cover.jpg")}-itunes"

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ItunesFeedImage.new.perform(suffixed_id)
      end
    end

    test "updates the feed when a legacy-only image hash is given" do
      processed_url = "https://cdn.example.com/cover.jpg"

      ItunesFeedImage.new.perform(@feed.id, {"processed_url" => processed_url})

      @feed.reload
      assert_equal processed_url, @feed.custom_icon
      assert_equal "square", @feed.custom_icon_format
    end

    # Row-backed: Upload already wrote the images row before enqueueing this
    # callback, so the metadata is not duplicated onto the feed. custom_icon
    # keeps its legacy value for readers still on the fallback path.
    test "keeps writing the legacy url and touches the feed when row-backed" do
      processed_url = "https://cdn.example.com/cover.jpg"
      # Pre-set every attribute receive writes, so the update is a no-op
      # and only the touch can move updated_at.
      @feed.update!(
        custom_icon: processed_url,
        custom_icon_format: "square",
        updated_at: 1.year.ago
      )
      before = @feed.reload.updated_at

      ItunesFeedImage.new.perform(@feed.id, {
        "processed_url" => processed_url,
        "storage_path" => "abc/abc123.jpg"
      })

      @feed.reload
      assert_equal processed_url, @feed.custom_icon
      assert_operator @feed.updated_at, :>, before
    end
  end
end
