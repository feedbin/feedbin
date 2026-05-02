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
      assert_equal [], args["image_urls"]
      assert_equal @page_url, args["entry_url"]
    end

    test "accepts a public_id with a trailing -suffix" do
      suffixed_id = "#{@entry.public_id}-twitter"

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        TwitterLinkImage.new.perform(suffixed_id, nil, @page_url)
      end
    end

    test "stores processed_url and placeholder_color into entry data when image is given" do
      image = {
        "processed_url" => "https://cdn.example.com/twitter.jpg",
        "placeholder_color" => "#abcdef"
      }

      TwitterLinkImage.new.perform(@entry.public_id, image)

      @entry.reload
      assert_equal image["processed_url"], @entry.data["twitter_link_image_processed"]
      assert_equal image["placeholder_color"], @entry.data["twitter_link_image_placeholder_color"]
    end
  end
end
