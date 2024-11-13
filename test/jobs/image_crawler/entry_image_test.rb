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
      <video poster="/video">
      <iframe src="/iframe"></iframe>
      <meta property="og:image" content="/og">
      <meta property="twitter:image" content="/twitter">
      <img src="/img">
      EOT

      entry = Feed.first.entries.create(
        content: content,
        public_id: SecureRandom.hex,
        url: "http://example.com"
      )

      EntryImage.new.perform(entry.public_id)

      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      extracted_urls = image.image_urls

      # should come back in the order of ImageCrawler::EntryImage::IMAGE_SELECTORS
      assert_equal "http://example.com/twitter", extracted_urls[0]
      assert_equal "http://example.com/og",      extracted_urls[1]
      assert_equal "http://example.com/img",     extracted_urls[2]
      assert_equal "http://example.com/iframe",  extracted_urls[3]
      assert_equal "http://example.com/video",   extracted_urls[4]

      assert_equal(entry.public_id, image.id)
      assert_equal(entry.fully_qualified_url, image.entry_url)
    end

    test "should enqueue Find with youtube url" do
      @entry.update(data: {youtube_video_id: "youtube_video_id"})
      @entry.reload
      EntryImage.new.perform(@entry.public_id)

      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      extracted_urls = image.image_urls
      assert_equal([@entry.url], extracted_urls)
    end

    test "should enqueue Find with tweet url" do
      entry = create_tweet_entry(Feed.first, "two")
      EntryImage.new.perform(entry.public_id)
      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      extracted_urls = image.image_urls
      assert_equal(["https://pbs.twimg.com/media/EwDoQHMVIAAGbaP.jpg"], extracted_urls)
    end

    test "should enqueue Find with media url" do
      xml = File.read(support_file("microposts.xml"))
      parsed = Feedkit::Parser::XMLFeed.new(xml, "http://example.com")
      feed = Feed.create_from_parsed_feed(parsed)
      entry = feed.entries.last
      pp entry.micropost?
      EntryImage.new.perform(entry.public_id)
      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      extracted_urls = image.image_urls
      assert_equal(["https://cdn.masto.host/frontendsocial/media_attachments/files/109/480/363/100/027/057/original/94aa051201c933c6.png", "https://cdn.masto.host/frontendsocial/media_attachments/files/109/480/363/321/232/707/original/fd91baf5af1de4eb.png", "https://cdn.masto.host/frontendsocial/media_attachments/files/109/480/363/513/928/252/original/005201b20fde9798.png"], extracted_urls)
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