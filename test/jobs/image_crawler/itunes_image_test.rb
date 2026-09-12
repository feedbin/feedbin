require "test_helper"

module ImageCrawler
  class ItunesImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @feed = Feed.first
      @feed.update(host: "example.com")
      @entry = @feed.entries.create!(
        public_id: SecureRandom.hex,
        url: "http://example.com/episode",
        data: {"itunes_image" => "http://example.com/cover.jpg"}
      )
    end

    test "schedules a Find job when no image is given" do
      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ItunesImage.new.perform(@entry.public_id)
      end

      args = Pipeline::Find.jobs.last["args"].first
      assert_equal "#{@entry.public_id}-itunes", args["id"]
      assert_equal "podcast", args["preset_name"]
      assert_equal ::Image.kinds[:cover_art], args["kind"]
      assert_equal ["http://example.com/cover.jpg"], args["image_urls"]
    end

    test "accepts a public_id with a trailing -suffix" do
      suffixed_id = "#{@entry.public_id}-itunes"

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ItunesImage.new.perform(suffixed_id)
      end
    end

    test "raises on a payload without storage_path" do
      assert_raises(KeyError) { ItunesImage.new.perform(@entry.public_id, {"processed_url" => "https://cdn.example.com/cover.jpg"}) }
      assert_nil @entry.reload.media_image
    end

    # Row-backed: Upload or Dedupe already wrote the images row before this
    # callback. media_image is a legacy pointer, and a row-backed callback
    # must not write one, or Dedupe keeps spreading legacy urls onto
    # entries the unified store already serves.
    test "does not write media_image when row-backed" do
      @entry.update!(media_image: nil, provider: nil, provider_id: nil)

      ItunesImage.new.perform(@entry.public_id, {
        "processed_url" => "https://bucket.s3.amazonaws.com/abc/legacy.jpg",
        "storage_path" => "abc/abc123.jpg"
      })

      @entry.reload
      assert_nil @entry.media_image
      assert_equal "entry_icon", @entry.provider
      assert_equal @entry.id.to_s, @entry.provider_id
    end

    test "skips processing when SKIP_IMAGES env var is set" do
      ENV["SKIP_IMAGES"] = "1"
      begin
        assert_no_difference -> { Pipeline::Find.jobs.size } do
          ItunesImage.new.perform(@entry.public_id)
        end
      ensure
        ENV.delete("SKIP_IMAGES")
      end
    end
  end
end
