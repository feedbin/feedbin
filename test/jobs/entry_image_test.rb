require "test_helper"

class EntryImageTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Queues["images"].clear
    @entry = Feed.first.entries.create(
      content: Faker::Lorem.paragraph,
      public_id: SecureRandom.hex,
    )
  end

  test "should enqueue FindImage" do
    assert_difference "Sidekiq::Queues['images'].count", +1 do
      EntryImage.new.perform(@entry.id)
    end
  end

  test "should add image to entry" do
    image = {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "http://cdn.example.com/image.jpg",
      "width" => 542,
      "height" => 304,
    }
    EntryImage.new.perform(@entry.id, image)
    assert_equal image, @entry.reload.image
  end

  test "should skip enqueue" do
    @entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "http://cdn.example.com/image.jpg",
      "width" => 542,
      "height" => 304,
    })
    assert_difference "Sidekiq::Queues['images'].count", 0 do
      EntryImage.new.perform(@entry.id)
    end
  end
end
