require "test_helper"

module ImageCrawler
  class EntryImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @feed = Feed.first
      @feed.update(host: "example.com")
      @feed.reload
      @entry = @feed.entries.create(
        content: Faker::Lorem.paragraph,
        public_id: SecureRandom.hex,
        url: "http://example.com"
      )
    end

    test "should enqueue Find" do
      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        EntryImage.new.perform(@entry.public_id)
      end
    end

    test "should enqueue Find with parsed urls" do

      content = <<-EOT
      <iframe src="/iframe"></iframe>
      <img src="/img">
      <video poster="/video">
      EOT

      entry = Feed.first.entries.create(
        content: content,
        public_id: SecureRandom.hex,
        url: "http://example.com"
      )

      EntryImage.new.perform(entry.public_id)

      extracted_urls = Pipeline::Find.jobs.first["args"][2]
      assert extracted_urls.include?("http://example.com/iframe")
      assert extracted_urls.include?("http://example.com/img")
      assert extracted_urls.include?("http://example.com/video")

      assert_equal(entry.public_id, Pipeline::Find.jobs.first["args"].first)
      assert_equal(entry.fully_qualified_url, Pipeline::Find.jobs.first["args"].last)
    end

    test "should enqueue Find with youtube url" do
      @entry.update(data: {youtube_video_id: "youtube_video_id"})
      @entry.reload
      EntryImage.new.perform(@entry.public_id)

      extracted_urls = Pipeline::Find.jobs.first["args"][2]
      assert_equal([@entry.url], extracted_urls)
    end

    test "should enqueue Find with tweet url" do
      entry = create_tweet_entry(Feed.first, "two")
      EntryImage.new.perform(entry.public_id)
      extracted_urls = Pipeline::Find.jobs.first["args"][2]
      assert_equal(["https://pbs.twimg.com/media/EwDoQHMVIAAGbaP.jpg"], extracted_urls)
    end

    test "should add image to entry" do
      image = {
        "original_url" => "http://example.com/image.jpg",
        "processed_url" => "http://cdn.example.com/image.jpg",
        "width" => 542,
        "height" => 304
      }
      EntryImage.new.perform(@entry.public_id, image)
      assert_equal image, @entry.reload.image
    end

    test "should skip enqueue" do
      @entry.update(image: {
        "original_url" => "http://example.com/image.jpg",
        "processed_url" => "http://cdn.example.com/image.jpg",
        "width" => 542,
        "height" => 304
      })
      assert_no_difference -> { Pipeline::Find.jobs.size } do
        EntryImage.new.perform(@entry.public_id)
      end
    end
  end
end