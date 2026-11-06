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

    assert_difference -> { Sidekiq.redis { it.scard(HarvestEmbeds::SET_NAME) } }, +1 do
      HarvestEmbeds.new.perform(@entry.id)
    end

  end

  test "should harvest from youtube feed" do
    @entry.update(data: {youtube_video_id: "video_id"})

    assert_difference -> { Sidekiq.redis { it.scard(HarvestEmbeds::SET_NAME) } }, +1 do
      HarvestEmbeds.new.perform(@entry.id)
    end
  end

  test "should create embed records" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    Sidekiq.redis { it.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
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
    assert_nil @feed.reload.settings["custom_icon"], "the channel row is the icon; nothing is copied out of the embed"
  end

  test "should survive a youtube response with no items" do
    # The ordinary answer when every id in the batch has been deleted, made
    # private, or region-blocked.
    stub_request(:get, %r{www.googleapis.com/youtube/v3/})
      .to_return(body: "{}", headers: {content_type: "application/json"})

    assert_nothing_raised do
      HarvestEmbeds::Download.new.perform(["video_id"])
    end
  end

  test "a video API timeout preserves existing embeds and skips the channel request" do
    embed = Embed.youtube_video.create!(provider_id: "video_id", data: {"snippet" => {"title" => "Existing title"}})
    stub_request(:get, %r{www.googleapis.com/youtube/v3/videos}).to_timeout

    assert_no_difference "Embed.count" do
      HarvestEmbeds::Download.new.perform(["video_id"])
    end

    assert_equal "Existing title", embed.reload.data.dig("snippet", "title")
    assert_not_requested :get, %r{www.googleapis.com/youtube/v3/channels}
  end

  test "a channel API timeout still saves the available video metadata" do
    stub_youtube_api
    stub_request(:get, %r{www.googleapis.com/youtube/v3/channels}).to_timeout

    HarvestEmbeds::Download.new.perform(["video_id"])

    video = Embed.youtube_video.find_by!(provider_id: "video_id")
    assert_equal "channel_id", video.parent_id
    assert_equal 9743, video.duration_in_seconds
    assert_nil Embed.youtube_channel.find_by(provider_id: "channel_id")
  end

  test "should add provider_parent_id from existing embed" do
    Embed.youtube_video.create!(provider_id: "video_id", parent_id: "channel_id", data: {})

    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    @entry.send(:provider_metadata)
    @entry.save!

    assert_equal("channel_id", @entry.reload.provider_parent_id)
  end

  # The entry's own <yt:channelId> outranks the embed lookup: known at
  # creation, and still there when the API round trip comes back empty.
  test "should take provider_parent_id from the entry's own channel id" do
    @entry.update(data: {youtube_video_id: "video_id", youtube_channel_id: "UCfromentry"}, provider_id: "video_id")
    @entry.provider_youtube!
    @entry.send(:provider_metadata)
    @entry.save!

    assert_equal("UCfromentry", @entry.reload.provider_parent_id)
  end

  test "should requeue live videos scheduled in the future" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    scheduled_time = 1.day.from_now
    Sidekiq.redis { it.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
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

    Sidekiq.redis { it.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
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
    assert_empty HarvestEmbeds::Download::Redownload.jobs
  end

  test "should not requeue videos with liveBroadcastContent none" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!

    Sidekiq.redis { it.sadd(HarvestEmbeds::SET_NAME, "video_id") } == 1
    stub_youtube_api(
      live_broadcast_content: "none",
      live_streaming_details: {
        scheduledStartTime: 1.day.from_now.iso8601
      }
    )

    HarvestEmbeds.new.perform(nil, true)
    assert_equal 1, HarvestEmbeds::Download.jobs.size

    # Manually execute the Download job
    job = HarvestEmbeds::Download.jobs.shift
    HarvestEmbeds::Download.new.perform(*job["args"])

    # No scheduled jobs should be created since liveBroadcastContent is none
    assert_empty HarvestEmbeds::Download::Redownload.jobs
  end

  test "records the iframed videos, not the linked ones, and still queues both" do
    @entry.update(content: %(<iframe src="https://www.youtube.com/embed/video_id"></iframe><a href="https://www.youtube.com/watch?v=link_id">x</a>))

    HarvestEmbeds.new.perform(@entry.id)

    assert_equal ["video_id"], EntryVideo.where(entry_id: @entry.id).pluck(:provider_id)
    assert_equal %w[link_id video_id], Sidekiq.redis { it.smembers(HarvestEmbeds::SET_NAME) }.sort
  end

  test "records a YouTube feed entry's own video" do
    @entry.update(data: {youtube_video_id: "video_id"})

    HarvestEmbeds.new.perform(@entry.id)

    assert_equal ["video_id"], EntryVideo.where(entry_id: @entry.id).pluck(:provider_id)
  end

  test "an entry whose video data was stored after it was created is marked edited" do
    @entry.update(content: %(<iframe src="https://www.youtube.com/embed/video_id"></iframe>))
    Embed.youtube_video.create!(provider_id: "video_id", data: {}, updated_at: @entry.created_at + 1.minute)

    HarvestEmbeds.new.perform(@entry.id)

    assert_equal 2, @entry.reload.revision
  end

  test "scanning an entry again does not mark it edited again" do
    @entry.update(content: %(<iframe src="https://www.youtube.com/embed/video_id"></iframe>))
    Embed.youtube_video.create!(provider_id: "video_id", data: {}, updated_at: @entry.created_at + 1.minute)

    HarvestEmbeds.new.perform(@entry.id)
    HarvestEmbeds.new.perform(@entry.id)

    assert_equal 2, @entry.reload.revision
  end

  test "an entry whose video data was stored before it was created is not marked edited" do
    @entry.update(content: %(<iframe src="https://www.youtube.com/embed/video_id"></iframe>))
    Embed.youtube_video.create!(provider_id: "video_id", data: {}, updated_at: @entry.created_at - 1.minute)

    HarvestEmbeds.new.perform(@entry.id)

    assert_equal 1, @entry.reload.revision
  end

  test "a download marks the entries showing the videos it stored edited" do
    other = create_entry(@feed)
    EntryVideo.record(entry_id: @entry.id, provider_ids: ["video_id"])
    EntryVideo.record(entry_id: other.id, provider_ids: ["missing_id"])
    stub_youtube_api

    HarvestEmbeds::Download.new.perform(["video_id", "missing_id"])

    @entry.reload
    assert_equal 2, @entry.revision
    assert_not_nil @entry.edited_at
    assert_equal 1, other.reload.revision
  end

  test "a redownload sees the stream's current state, not a cached answer" do
    stub_youtube_api(live_broadcast_content: "live", live_streaming_details: {scheduledStartTime: 1.hour.ago.iso8601})
    HarvestEmbeds::Download.new.perform(["video_id"])
    assert_equal "live", Embed.youtube_video.find_by(provider_id: "video_id").live_broadcast_content

    stub_youtube_api(live_broadcast_content: "none")
    HarvestEmbeds::Download.new.perform(["video_id"])
    assert_equal "none", Embed.youtube_video.find_by(provider_id: "video_id").live_broadcast_content
  end

  test "a failed video request puts the ids back in the queue" do
    stub_request(:get, %r{www.googleapis.com/youtube/v3/videos}).to_return(status: 503)

    HarvestEmbeds::Download.new.perform(["video_id", "other_id"])

    assert_equal ["other_id", "video_id"], Sidekiq.redis { it.smembers(HarvestEmbeds::SET_NAME) }.sort
  end

  test "an exhausted quota puts the ids back and pauses harvesting until the quota resets" do
    stub_request(:get, %r{www.googleapis.com/youtube/v3/videos})
      .to_return(status: 403, body: {error: {errors: [{reason: "quotaExceeded"}]}}.to_json)

    HarvestEmbeds::Download.new.perform(["video_id"])

    assert_equal ["video_id"], Sidekiq.redis { it.smembers(HarvestEmbeds::SET_NAME) }
    HarvestEmbeds.new.perform(nil, true)
    assert_empty HarvestEmbeds::Download.jobs, "no downloads until the quota resets"
    assert_equal ["video_id"], Sidekiq.redis { it.smembers(HarvestEmbeds::SET_NAME) }
  end

  test "downloading unchanged data does not mark entries edited again" do
    EntryVideo.record(entry_id: @entry.id, provider_ids: ["video_id"])
    stub_youtube_api(live_broadcast_content: "upcoming", live_streaming_details: {scheduledStartTime: 1.hour.from_now.iso8601})

    HarvestEmbeds::Download.new.perform(["video_id"])
    assert_equal 2, @entry.reload.revision

    HarvestEmbeds::Download.new.perform(["video_id"])
    assert_equal 2, @entry.reload.revision, "nothing changed"

    stub_youtube_api(live_broadcast_content: "live", live_streaming_details: {scheduledStartTime: 1.hour.from_now.iso8601})
    HarvestEmbeds::Download.new.perform(["video_id"])
    assert_equal 3, @entry.reload.revision, "the stream went live"
  end

  test "requeues a live stream that has no scheduled start" do
    stub_youtube_api(live_broadcast_content: "live", live_streaming_details: {actualStartTime: 10.minutes.ago.iso8601})

    HarvestEmbeds::Download.new.perform(["video_id"])

    job = HarvestEmbeds::Download::Redownload.jobs.last
    assert_equal ["video_id"], job["args"]
    assert_in_delta 1.hour.from_now.to_f, job["at"], 5.0
  end

  test "does not requeue a stream that has ended" do
    stub_youtube_api(live_broadcast_content: "live", live_streaming_details: {
      scheduledStartTime: 2.hours.ago.iso8601,
      actualStartTime: 2.hours.ago.iso8601,
      actualEndTime: 5.minutes.ago.iso8601
    })

    HarvestEmbeds::Download.new.perform(["video_id"])

    assert_empty HarvestEmbeds::Download::Redownload.jobs
  end

  test "a download leaves an entry whose video fields already match unsaved" do
    stub_youtube_api
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    @entry.update(provider_parent_id: "channel_id", embed_duration: 9743)
    HarvestEmbeds.jobs.clear

    HarvestEmbeds::Download.new.perform(["video_id"])

    assert_empty HarvestEmbeds.jobs, "an unchanged entry runs no update callbacks"
  end

  test "an unchanged channel with an avatar is not crawled again" do
    stub_youtube_api
    HarvestEmbeds::Download.new.perform(["video_id"])
    create_image_row(provider: :embed_icon, provider_id: "channel_id", kind: :avatar, feed_id: nil, variant: "200x200")

    assert_no_difference -> { ImageCrawler::Pipeline::Find.jobs.size } do
      HarvestEmbeds::Download.new.perform(["video_id"])
    end
  end

  test "an unchanged channel with no avatar yet is crawled again" do
    stub_youtube_api
    HarvestEmbeds::Download.new.perform(["video_id"])

    assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +1 do
      HarvestEmbeds::Download.new.perform(["video_id"])
    end
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
              },
              high: {
                url: "https://yt3.ggpht.com/avatar.jpg"
              }
            }
          },
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/channels})
      .to_return body: channels.to_json, headers: {content_type: "application/json"}

    stub_request_file("image.png", "https://yt3.ggpht.com/avatar.jpg", headers: {content_type: "image/png"})
  end

  test "schedules the channel avatar with every thumbnail as a candidate" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    Sidekiq.redis { it.sadd(HarvestEmbeds::SET_NAME, "video_id") }
    stub_youtube_api

    HarvestEmbeds.new.perform(nil, true)
    job = HarvestEmbeds::Download.jobs.shift

    assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +1 do
      HarvestEmbeds::Download.new.perform(*job["args"])
    end

    args = ImageCrawler::Pipeline::Find.jobs.last["args"].first
    assert_equal ["https://yt3.ggpht.com/avatar.jpg", "image_url"], args["image_urls"]
    assert_equal "channel_avatar", args["preset_name"]
    assert_equal "channel_id", args["provider_id"]
  end

  test "survives videos whose channel embed was never imported" do
    Embed.youtube_video.create!(provider_id: "video_id", parent_id: "channel_id", data: {})

    assert_nothing_raised do
      HarvestEmbeds::Download.new.send(:update_related_records, ["video_id"], [])
    end
  end
end
