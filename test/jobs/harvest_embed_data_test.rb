require "test_helper"

class HarvestEmbedDataTest < ActiveSupport::TestCase
  setup do

  test "should create embed records" do
    Sidekiq.redis {|r| r.sadd(HarvestEmbeds::SET_NAME, "id") }

    stub_youtube_api

    assert_difference "Embed.count", +2 do
      HarvestEmbedData.new.perform
    end

  end

  def stub_youtube_api
    videos = {
      items: [
        {
          id: "video_id",
          snippet: {
            channelId: "channel_id"
          }
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/videos})
      .to_return body: videos.to_json, headers: {content_type: "application/json"}

    channels = {
      items: [
        {
          id: "channel_id"
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/channels})
      .to_return body: channels.to_json, headers: {content_type: "application/json"}
  end

end
