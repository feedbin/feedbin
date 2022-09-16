require "test_helper"

module FeedCrawler
  class YoutubeReceiverTest < ActiveSupport::TestCase
    setup do
      @user = users(:ben)
      @subscription = @user.subscriptions.first
      @feed = @subscription.feed
    end

    test "should create entry with embed content" do
      embed_id = "embed_id"
      content = "content"
      public_id = SecureRandom.hex
      Embed.youtube_video.create!(provider_id: embed_id, data: {
        "snippet" => {
          "description" => content
        }
      })

      data = {
        "feed" => {"id" => @feed.id},
        "entries" => [{
          "title" => "title",
          "public_id" => public_id,
          "data" => {"youtube_video_id" => embed_id}
        }]
      }

      YoutubeReceiver.new.perform(data)

      entry = Entry.find_by_public_id!(public_id)

      assert_equal(content, entry.content)
    end
  end
end