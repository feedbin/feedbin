require "test_helper"

class EmbedTest < ActiveSupport::TestCase
  test "duration_in_seconds parses ISO 8601 duration with hours, minutes and seconds" do
    embed = Embed.new(source: :youtube_video, provider_id: "v1", data: {
      "contentDetails" => {"duration" => "PT1H2M3S"}
    })

    assert_equal 3723, embed.duration_in_seconds
  end

  test "duration_in_seconds parses minutes and seconds only" do
    embed = Embed.new(source: :youtube_video, provider_id: "v2", data: {
      "contentDetails" => {"duration" => "PT5M30S"}
    })

    assert_equal 330, embed.duration_in_seconds
  end

  test "duration_in_seconds returns nil when no duration is present" do
    embed = Embed.new(source: :youtube_video, provider_id: "v3", data: {})
    assert_nil embed.duration_in_seconds
  end

  test "live_broadcast_content reads from snippet" do
    embed = Embed.new(source: :youtube_video, provider_id: "v4", data: {
      "snippet" => {"liveBroadcastContent" => "live"}
    })

    assert_equal "live", embed.live_broadcast_content
  end

  test "scheduled_start_time reads from liveStreamingDetails" do
    embed = Embed.new(source: :youtube_video, provider_id: "v5", data: {
      "liveStreamingDetails" => {"scheduledStartTime" => "2026-01-15T10:00:00Z"}
    })

    assert_equal "2026-01-15T10:00:00Z", embed.scheduled_start_time
  end

  test "scheduled_time parses scheduled_start_time into a Time" do
    embed = Embed.new(source: :youtube_video, provider_id: "v6", data: {
      "liveStreamingDetails" => {"scheduledStartTime" => "2026-01-15T10:00:00Z"}
    })

    assert_equal Time.parse("2026-01-15T10:00:00Z"), embed.scheduled_time
  end

  test "scheduled_time is nil when no scheduled_start_time exists" do
    embed = Embed.new(source: :youtube_video, provider_id: "v7", data: {})
    assert_nil embed.scheduled_time
  end

  test "channel returns nil for non-video embeds" do
    embed = Embed.create!(source: :youtube_channel, provider_id: "channel-1", data: {})
    assert_equal false, embed.channel
  end

  test "channel finds the parent channel embed for a video" do
    channel = Embed.create!(source: :youtube_channel, provider_id: "channel-1", data: {})
    video = Embed.create!(source: :youtube_video, provider_id: "video-1", parent_id: "channel-1", data: {})

    assert_equal channel, video.channel
  end

  test "chapters memoizes and delegates to TextToChapters" do
    embed = Embed.new(source: :youtube_video, provider_id: "v8", data: {
      "snippet" => {"description" => "00:00 Intro\n01:00 Topic"},
      "contentDetails" => {"duration" => "PT5M"}
    })

    chapters = embed.chapters
    assert_kind_of Array, chapters
    assert_same chapters, embed.chapters
  end

  test "chapters handles missing description gracefully" do
    embed = Embed.new(source: :youtube_video, provider_id: "v9", data: {
      "contentDetails" => {"duration" => "PT5M"}
    })

    assert_nothing_raised { embed.chapters }
  end
end
