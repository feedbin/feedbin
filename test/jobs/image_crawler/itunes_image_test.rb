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
      assert_equal ["http://example.com/cover.jpg"], args["image_urls"]
    end

    test "accepts a public_id with a trailing -suffix" do
      suffixed_id = "#{@entry.public_id}-itunes"

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ItunesImage.new.perform(suffixed_id)
      end
    end

    test "updates the entry when a legacy-only image hash is given" do
      processed_url = "https://cdn.example.com/cover.jpg"

      ItunesImage.new.perform(@entry.public_id, {"processed_url" => processed_url})

      @entry.reload
      assert_equal processed_url, @entry.media_image
      assert_equal "entry_icon", @entry.provider
      assert_equal @entry.id.to_s, @entry.provider_id
    end

    # Row-backed: Upload already wrote the images row before enqueueing this
    # callback, so the metadata is not duplicated onto the entry. media_image
    # keeps its legacy value for readers still on the fallback path.
    test "keeps writing the legacy url and does not touch the entry when row-backed" do
      processed_url = "https://cdn.example.com/cover.jpg"
      # Pre-set every attribute receive writes -- media_image, provider, and
      # provider_id -- to what it will write again, the way a re-crawl of
      # unchanged artwork finds the entry in production. That makes the
      # update a true no-op, so this proves updated_at truly does not move --
      # there is no touch to catch a regression that silently reintroduces
      # one. No cached view renders episode artwork keyed on this entry (see
      # receive's comment), so there is nothing for a touch to keep fresh.
      @entry.update!(
        media_image: processed_url,
        provider: :entry_icon,
        provider_id: @entry.id,
        updated_at: 1.year.ago
      )
      before = @entry.reload.updated_at

      ItunesImage.new.perform(@entry.public_id, {
        "processed_url" => processed_url,
        "storage_path" => "abc/abc123.jpg"
      })

      @entry.reload
      assert_equal processed_url, @entry.media_image
      assert_equal before, @entry.updated_at
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
