require "test_helper"

class Api::V3::VideoSerializerTest < ActiveSupport::TestCase
  test "a harvested video with its channel" do
    video = video_embed(
      thumbnails: {
        "maxres" => {"url" => "https://i.ytimg.com/vi/AAA/maxresdefault.jpg", "width" => 1280, "height" => 720},
        "high" => {"url" => "https://i.ytimg.com/vi/AAA/hqdefault.jpg", "width" => 480, "height" => 360}
      }
    )
    channel = Embed.create!(source: :youtube_channel, provider_id: "UC1", data: {"snippet" => {"title" => "Channel"}})
    image = create_image_row(provider: :embed_icon, provider_id: "UC1", kind: :avatar)

    json = Api::V3::VideoSerializer.new(video, channel: channel, channel_image: image).to_h

    assert_equal({
      object: "video",
      provider: "youtube",
      id: "AAA",
      url: "https://youtu.be/AAA",
      title: "A video",
      duration_in_seconds: 213,
      live: "none",
      scheduled_start_at: nil,
      poster: {url: "https://i.ytimg.com/vi/AAA/maxresdefault.jpg", width: 1280, height: 720},
      channel: {id: "UC1", title: "Channel", icon: Api::V3::ImageSerializer.new(image).to_h},
      chapters: [
        {start_in_seconds: 0, title: "Intro", duration_in_seconds: 42},
        {start_in_seconds: 42, title: "Song", duration_in_seconds: 171}
      ]
    }, json)
  end

  test "the poster is the largest thumbnail listed" do
    video = video_embed(
      thumbnails: {
        "default" => {"url" => "https://i.ytimg.com/vi/AAA/default.jpg", "width" => 120, "height" => 90},
        "high" => {"url" => "https://i.ytimg.com/vi/AAA/hqdefault.jpg", "width" => 480, "height" => 360}
      }
    )

    assert_equal({url: "https://i.ytimg.com/vi/AAA/hqdefault.jpg", width: 480, height: 360}, Api::V3::VideoSerializer.new(video).to_h[:poster])
  end

  test "no thumbnails is no poster" do
    assert_nil Api::V3::VideoSerializer.new(video_embed(thumbnails: nil)).to_h[:poster]
  end

  test "a video without its channel row has no channel" do
    assert_nil Api::V3::VideoSerializer.new(video_embed).to_h[:channel]
  end

  test "a channel whose avatar isn't crawled has no icon" do
    channel = Embed.create!(source: :youtube_channel, provider_id: "UC1", data: {"snippet" => {"title" => "Channel"}})

    json = Api::V3::VideoSerializer.new(video_embed, channel: channel).to_h

    assert_equal({id: "UC1", title: "Channel", icon: nil}, json[:channel])
  end

  test "an upcoming stream" do
    video = Embed.create!(source: :youtube_video, provider_id: "BBB", parent_id: "UC1", data: {
      "snippet" => {"title" => "Soon", "liveBroadcastContent" => "upcoming"},
      "liveStreamingDetails" => {"scheduledStartTime" => "2026-11-04T18:00:00Z"}
    })

    json = Api::V3::VideoSerializer.new(video).to_h

    assert_equal "upcoming", json[:live]
    assert_equal "2026-11-04T18:00:00Z", json[:scheduled_start_at]
    assert_nil json[:duration_in_seconds]
    assert_equal [], json[:chapters]
  end

  private

  def video_embed(thumbnails: {})
    Embed.create!(source: :youtube_video, provider_id: "AAA", parent_id: "UC1", data: {
      "snippet" => {
        "title" => "A video",
        "description" => "Chapters:\n0:00 Intro\n0:42 Song\n",
        "liveBroadcastContent" => "none",
        "thumbnails" => thumbnails
      }.compact,
      "contentDetails" => {"duration" => "PT3M33S"}
    })
  end
end
