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
    stub_youtube_api(
      live_broadcast_content: "live",
      live_streaming_details: {
        actualStartTime: "2021-12-08T13:50:11Z",
        scheduledStartTime: "2021-12-08T13:45:00Z"
      }
    )

    Sidekiq::Testing.inline! do
      assert_difference "Embed.count", +2 do
        HarvestEmbeds.new.perform(nil, true)
      end
    end

    assert_equal("channel_id", @entry.reload.provider_parent_id)
    assert_equal(9743, @entry.reload.embed_duration)
    assert_equal("image_url", @feed.reload.custom_icon)
  end

  test "should add provider_parent_id from existing embed" do
    Embed.youtube_video.create!(provider_id: "video_id", parent_id: "channel_id", data: {})

    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    @entry.send(:provider_metadata)
    @entry.save!

    assert_equal("channel_id", @entry.reload.provider_parent_id)
  end

  test "should requeue live videos scheduled in the future" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    scheduled_time = 1.day.from_now
    Sidekiq.redis { _1.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
    stub_youtube_api(
      live_broadcast_content: "upcoming",
      live_streaming_details: {
        scheduledStartTime: scheduled_time.iso8601
      }
    )

    # Run cache_embeds to create the first job
    HarvestEmbeds.new.perform(nil, true)
    assert_equal 1, HarvestEmbeds::Download.jobs.size

    # Manually execute the Download job (not inline mode to avoid infinite recursion)
    job = HarvestEmbeds::Download.jobs.shift
    HarvestEmbeds::Download.new.perform(*job["args"])

    # Check that a scheduled job was created for 1 hour after scheduled_time
    assert_equal 1, HarvestEmbeds::Download::Redownload.jobs.size
    scheduled_job = HarvestEmbeds::Download::Redownload.jobs.last
    expected_time = scheduled_time + 1.hour
    assert_in_delta expected_time.to_f, scheduled_job["at"], 1.0
    assert_equal ["video_id"], scheduled_job["args"]
  end

  test "should not requeue live videos scheduled more than 24 hours ago" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    Sidekiq.redis { _1.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
    stub_youtube_api(
      live_broadcast_content: "live",
      live_streaming_details: {
        actualStartTime: "2021-12-08T13:50:11Z",
        scheduledStartTime: "2021-12-08T13:45:00Z"
      }
    )

    HarvestEmbeds.new.perform(nil, true)
    assert_equal 1, HarvestEmbeds::Download.jobs.size

    # Manually execute the Download job
    job = HarvestEmbeds::Download.jobs.shift
    HarvestEmbeds::Download.new.perform(*job["args"])

    # No scheduled jobs should be created since scheduled time is more than 24 hours ago
    assert_equal 0, HarvestEmbeds::Download.jobs.size
  end

  test "should not requeue videos with liveBroadcastContent none" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    Sidekiq.redis { _1.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
    stub_youtube_api(live_broadcast_content: "none")

    HarvestEmbeds.new.perform(nil, true)
    assert_equal 1, HarvestEmbeds::Download.jobs.size

    # Manually execute the Download job
    job = HarvestEmbeds::Download.jobs.shift
    HarvestEmbeds::Download.new.perform(*job["args"])

    # No scheduled jobs should be created since liveBroadcastContent is none
    assert_equal 0, HarvestEmbeds::Download.jobs.size
  end

  def stub_youtube_api(live_broadcast_content: "none", live_streaming_details: nil)
    video_item = {
      id: "video_id",
      snippet: {
        channelId: "channel_id",
        liveBroadcastContent: live_broadcast_content
      },
      contentDetails: {
        duration: "PT2H42M23S",
      }
    }
    video_item[:liveStreamingDetails] = live_streaming_details if live_streaming_details

    videos = {
      items: [video_item]
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
