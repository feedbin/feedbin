require "test_helper"

class EntryImageTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Queues["images"].clear
    @entry = Feed.first.entries.create(
      content: Faker::Lorem.paragraph,
      public_id: SecureRandom.hex,
      url: "http://example.com"
    )
  end

  test "should enqueue FindImage" do
    assert_difference "Sidekiq::Queues['images'].count", +1 do
      EntryImage.new.perform(@entry.id)
    end
  end

  test "should enqueue FindImage with parsed urls" do

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

    EntryImage.new.perform(entry.id)

    extracted_urls = Sidekiq::Queues['images'].first["args"][1]
    assert extracted_urls.include?("http://example.com/iframe")
    assert extracted_urls.include?("http://example.com/img")
    assert extracted_urls.include?("http://example.com/video")

    assert_equal(entry.public_id, Sidekiq::Queues['images'].first["args"].first)
    assert_equal(entry.fully_qualified_url, Sidekiq::Queues['images'].first["args"].last)
  end

  test "should enqueue FindImage with youtube url" do
    @entry.update(data: {youtube_video_id: "youtube_video_id"})
    @entry.reload
    EntryImage.new.perform(@entry.id)
    extracted_urls = Sidekiq::Queues['images'].first["args"][1]
    assert_equal([@entry.url], extracted_urls)
  end

  test "should enqueue FindImage with tweet url" do
    entry = create_tweet_entry(Feed.first, "two")
    EntryImage.new.perform(entry.id)
    extracted_urls = Sidekiq::Queues['images'].first["args"][1]
    assert_equal(["https://pbs.twimg.com/media/EwDoQHMVIAAGbaP.jpg"], extracted_urls)
  end

  test "should add image to entry" do
    image = {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "http://cdn.example.com/image.jpg",
      "width" => 542,
      "height" => 304
    }
    EntryImage.new.perform(@entry.id, image)
    assert_equal image, @entry.reload.image
  end

  test "should skip enqueue" do
    @entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "http://cdn.example.com/image.jpg",
      "width" => 542,
      "height" => 304
    })
    assert_difference "Sidekiq::Queues['images'].count", 0 do
      EntryImage.new.perform(@entry.id)
    end
  end
end
