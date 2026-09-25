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

    test "does nothing for a deleted entry" do
      assert_no_difference -> { Pipeline::Find.jobs.size } do
        ItunesImage.new.perform(SecureRandom.hex)
      end
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
