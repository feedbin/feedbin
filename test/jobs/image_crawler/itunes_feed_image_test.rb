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
      assert_equal ::Image.kinds[:cover_art], args["kind"]
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

    # No callback carries a legacy-only payload now that podcast_feed writes
    # the unified store only. A payload without storage_path is a regression,
    # and it must raise rather than write a legacy pointer onto the feed.
    test "raises on a payload without storage_path" do
      assert_raises(KeyError) { ItunesFeedImage.new.perform(@feed.id, {"processed_url" => "https://cdn.example.com/cover.jpg"}) }
      assert_nil @feed.reload.settings["custom_icon"]
    end

    # Row-backed: the feed_icon row is the read path and its kind is the
    # shape. The callback's only feed write is the touch, which busts the
    # cached views because new artwork can land under the same path.
    test "touches the feed and writes nothing else on it" do
      @feed.update!(updated_at: 1.year.ago)
      settings = @feed.reload.settings.dup
      before = @feed.updated_at

      ItunesFeedImage.new.perform(@feed.id, {
        "processed_url" => nil,
        "storage_path" => "abc/abc123.jpg"
      })

      @feed.reload
      assert_equal settings, @feed.settings
      assert_operator @feed.updated_at, :>, before
    end
  end
end
