require 'test_helper'

class BackfillProviderIdsTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
  end

  test "processes tweet entries correctly" do
    entry = create_tweet_entry(@feeds.first)
    entry.update(provider_id: nil, provider_parent_id: nil, image_provider_id: nil)

    BackfillProviderIds.new.perform(1)

    entry.reload
    assert_equal "952239648633491457", entry.provider_id
    assert_equal "twitter", entry.provider
    assert_equal "JeffBenjam", entry.image_provider_id
  end

  test "processes YouTube entries correctly" do
    entry = create_entry(@feeds.first)
    entry.update(provider_id: nil, provider_parent_id: nil, image_provider_id: nil)

    youtube_video_id = "youtube_video_id"
    youtube_channel_id = "youtube_channel_id"

    entry.update!(
      data: { "youtube_video_id" => youtube_video_id }
    )

    Embed.youtube_video.create!(provider_id: youtube_video_id, parent_id: youtube_channel_id, data: {
      "contentDetails" => {
        "duration" => "PT1H2M49S"
      }
    })

    BackfillProviderIds.new.perform(1)

    entry.reload
    assert_equal youtube_video_id, entry.provider_id
    assert_equal "youtube", entry.provider
    assert_equal youtube_channel_id, entry.provider_parent_id
    assert_equal youtube_channel_id, entry.image_provider_id
  end

  test "processes page entries correctly" do
    # Create a mock page entry
    feed = @feeds.first
    feed.pages!
    entry = create_entry(@feeds.first)
    entry.update(provider_id: nil, provider_parent_id: nil, image_provider_id: nil)

    BackfillProviderIds.new.perform(1)

    entry.reload
    assert_equal entry.hostname, entry.image_provider_id
    assert_equal "favicon", entry.provider
  end
end