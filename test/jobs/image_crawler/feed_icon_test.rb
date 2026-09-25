require "test_helper"

module ImageCrawler
  class FeedIconTest < ActiveSupport::TestCase
    setup do
      flush_redis
      Sidekiq::Worker.clear_all
      @feed = Feed.first
      @feed.update!(host: "example.com")
    end

    def find_args
      Pipeline::Find.jobs.last["args"].first
    end

    test "a podcast feed is the itunes job's, and schedules nothing" do
      @feed.update!(options: {"itunes_image" => "http://example.com/cover.jpg", "json_feed" => {"icon" => "http://example.com/icon.png"}})

      assert_no_difference -> { Pipeline::Find.jobs.size } do
        assert_equal false, FeedIcon.schedule(@feed)
      end
    end

    test "a json feed icon is a square site icon" do
      @feed.update!(options: {"json_feed" => {"icon" => "http://example.com/icon.png"}})

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        assert_equal true, FeedIcon.schedule(@feed)
      end

      args = find_args
      assert_equal "#{@feed.id}-#{Digest::SHA1.hexdigest("http://example.com/icon.png")}-icon", args["id"]
      assert_equal "feed_icon", args["preset_name"]
      assert_equal ::Image.kinds[:site_icon], args["kind"]
      assert_equal ::Image.providers[:feed_icon], args["provider"]
      assert_equal @feed.id, args["provider_id"]
      assert_equal ["http://example.com/icon.png"], args["image_urls"]
    end

    # micro.blog's feed.json puts the author's avatar in "icon": for a feed
    # of posts the icon is a person, not a site, and renders round.
    test "a micropost json feed icon is a round avatar" do
      create_entry(@feed).update!(title: nil)
      @feed.update!(options: {"json_feed" => {"icon" => "http://example.com/icon.png"}})

      FeedIcon.schedule(@feed)

      assert_equal ::Image.kinds[:avatar], find_args["kind"]
    end

    test "a json feed author avatar is a round avatar, ranked after the icon" do
      @feed.update!(options: {"json_feed" => {"author" => {"avatar" => "http://example.com/me.png"}}})
      FeedIcon.schedule(@feed)
      assert_equal ::Image.kinds[:avatar], find_args["kind"]
      assert_equal ["http://example.com/me.png"], find_args["image_urls"]

      @feed.update!(options: {"json_feed" => {"icon" => "http://example.com/icon.png", "author" => {"avatar" => "http://example.com/me.png"}}})
      FeedIcon.schedule(@feed)
      assert_equal ["http://example.com/icon.png"], find_args["image_urls"]
    end

    test "the rss image is an avatar for a micropost feed and ranks first" do
      create_entry(@feed).update!(title: nil)
      @feed.update!(options: {"image" => {"url" => "http://example.com/logo.png"}, "json_feed" => {"icon" => "http://example.com/icon.png"}})

      assert_equal true, FeedIcon.schedule(@feed)
      assert_equal ::Image.kinds[:avatar], find_args["kind"]
      assert_equal ["http://example.com/logo.png"], find_args["image_urls"]
    end

    test "the rss image is declined for a feed with titles" do
      create_entry(@feed).update!(title: "An article")
      @feed.update!(options: {"image" => {"url" => "http://example.com/logo.png"}})

      assert_no_difference -> { Pipeline::Find.jobs.size } do
        assert_equal false, FeedIcon.schedule(@feed)
      end
    end

    test "schedules nothing when the feed has no source" do
      @feed.update!(options: {})

      assert_no_difference -> { Pipeline::Find.jobs.size } do
        assert_equal false, FeedIcon.schedule(@feed)
      end
    end

    # "cdn.example.net/icon.png" is a path to a browser and a host to the
    # heuristic parser. Both readings go in, the strict one first.
    test "offers both readings of a scheme-less icon url" do
      Feed.where(id: @feed.id).update_all(feed_url: "http://example.com/feed/index.json")
      @feed.reload.update!(options: {"json_feed" => {"icon" => "cdn.example.net/icon.png"}})

      FeedIcon.schedule(@feed)

      assert_equal ["http://example.com/feed/cdn.example.net/icon.png", "http://cdn.example.net/icon.png"], find_args["image_urls"]
    end

    test "makes a relative url absolute against the feed" do
      # feed_url is attr_readonly, so it cannot be changed via update!; go
      # around ActiveRecord's instance-level readonly check with update_all.
      Feed.where(id: @feed.id).update_all(feed_url: "http://example.com/feed/index.json")
      @feed.reload.update!(options: {"json_feed" => {"icon" => "/icon.png"}})

      FeedIcon.schedule(@feed)

      assert_equal ["http://example.com/icon.png"], find_args["image_urls"]
    end

    test "perform with a feed id schedules, and accepts a suffixed id" do
      @feed.update!(options: {"json_feed" => {"icon" => "http://example.com/icon.png"}})
      suffixed = "#{@feed.id}-#{Digest::SHA1.hexdigest("http://example.com/icon.png")}-icon"

      assert_difference -> { Pipeline::Find.jobs.size }, +2 do
        FeedIcon.new.perform(@feed.id)
        FeedIcon.new.perform(suffixed)
      end
    end

    test "perform with an unknown feed does nothing" do
      assert_nothing_raised { FeedIcon.new.perform(0) }
      assert_empty Pipeline::Find.jobs
    end

    # The row is the read path; the callback's only job is to move the
    # feed's cache keys. It writes nothing else on the feed.
    test "receive touches the feed and writes nothing else" do
      @feed.update!(updated_at: 1.year.ago)
      settings = @feed.reload.settings.dup
      before = @feed.updated_at

      FeedIcon.new.perform(@feed.id, {"storage_path" => "abc/abc123.png", "provider_id" => @feed.id.to_s})

      @feed.reload
      assert_operator @feed.updated_at, :>, before
      assert_equal settings, @feed.settings
    end

    test "the feed_icon preset is png, content addressed, and calls back here" do
      preset = Image.new(preset_name: "feed_icon").preset

      assert_equal 200, preset.width
      assert_equal 200, preset.height
      assert_equal :limit_png, preset.crop
      assert_equal "png", preset.format
      assert preset.content_addressed
      assert_equal FeedIcon, preset.job_class
    end
  end
end
