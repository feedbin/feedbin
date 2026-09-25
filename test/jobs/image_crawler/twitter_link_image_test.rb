require "test_helper"

module ImageCrawler
  class TwitterLinkImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @feed = Feed.first
      @feed.update(host: "example.com")
      @entry = @feed.entries.create!(
        public_id: SecureRandom.hex,
        url: "http://example.com/tweet",
        data: {}
      )
      @page_url = "http://example.com/linked-article"
    end

    test "schedules a Find job when no image is given" do
      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        TwitterLinkImage.new.perform(@entry.public_id, nil, @page_url)
      end

      args = Pipeline::Find.jobs.last["args"].first
      assert_equal "#{@entry.public_id}-twitter", args["id"]
      assert_equal "twitter", args["preset_name"]
      assert_equal ::Image.kinds[:poster], args["kind"]
      assert_equal [], args["image_urls"]
      assert_equal @page_url, args["entry_url"]
    end

    test "accepts a public_id with a trailing -suffix" do
      suffixed_id = "#{@entry.public_id}-twitter"

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        TwitterLinkImage.new.perform(suffixed_id, nil, @page_url)
      end
    end

    test "should enqueue Find with feed context" do
      entry = Feed.first.entries.create(
        content: "content",
        public_id: SecureRandom.hex,
        url: "http://example.com/article"
      )

      TwitterLinkImage.new.perform(entry.public_id, nil, "http://example.com/linked-page")

      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      assert_equal entry.feed_id, image.feed_id
      assert_equal "http://example.com/linked-page", image.page_url
      assert_equal "http://example.com/linked-page", image.entry_url
    end

    test "does nothing for a deleted entry" do
      assert_no_difference -> { Pipeline::Find.jobs.size } do
        TwitterLinkImage.new.perform("#{SecureRandom.hex}-twitter", nil, @page_url)
      end
    end

    test "the callback touches the entry and writes nothing onto it" do
      @entry.update_column(:updated_at, 1.year.ago)
      before = @entry.reload.updated_at

      TwitterLinkImage.new.perform("#{@entry.public_id}-twitter", {"storage_path" => "abc/abcdef.jpg", "provider_id" => @entry.id.to_s})

      @entry.reload
      assert_operator @entry.updated_at, :>, before
      assert_equal({}, @entry.data)
    end
  end
end
