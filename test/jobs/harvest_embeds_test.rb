require "test_helper"

class HarvestEmbedsTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @user = users(:ben)
    @feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=channel_id")
    @entry = create_entry(@feed)
  end

  test "should harvest from iframe" do
    @entry.update(content: %(<iframe src="http://www.youtube.com/embed/video_id"></iframe>))

    assert_difference -> { Sidekiq.redis { _1.scard(HarvestEmbeds::SET_NAME) } }, +1 do
      HarvestEmbeds.new.perform(@entry.id)
    end

  end

  test "should harvest from youtube feed" do
    @entry.update(data: {youtube_video_id: "video_id"})

    assert_difference -> { Sidekiq.redis { _1.scard(HarvestEmbeds::SET_NAME) } }, +1 do
      HarvestEmbeds.new.perform(@entry.id)
    end
  end

  test "should create embed records" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    Sidekiq.redis { _1.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
    stub_youtube_api

    Sidekiq::Testing.inline! do
      assert_difference "Embed.count", +2 do
        HarvestEmbeds.new.perform(nil, true)
      end
    end

    assert_equal("channel_id", @entry.reload.provider_parent_id)
    assert_equal(9743, @entry.reload.embed_duration)
    assert_equal("image_url", @feed.reload.custom_icon)
    pp
  end

  test "should add provider_parent_id from existing embed" do
    Embed.youtube_video.create!(provider_id: "video_id", parent_id: "channel_id", data: {})

    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    @entry.send(:provider_metadata)
    @entry.save!

    assert_equal("channel_id", @entry.reload.provider_parent_id)
  end

  def stub_youtube_api
    videos = {
      items: [
        {
          id: "video_id",
          snippet: {
            channelId: "channel_id",
          },
          contentDetails: {
            duration: "PT2H42M23S",
          }
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/videos})
      .to_return body: videos.to_json, headers: {content_type: "application/json"}

    channels = {
      items: [
        {
          id: "channel_id",
          snippet: {
            thumbnails: {
              default: {
                url: "image_url"
              }
            }
          },
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/channels})
      .to_return body: channels.to_json, headers: {content_type: "application/json"}
  end


end
