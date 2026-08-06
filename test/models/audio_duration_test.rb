require "test_helper"

class AudioDurationTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
  end

  def episode(itunes_duration = nil)
    data = {"enclosure_url" => "http://example.com/ep.mp3", "enclosure_type" => "audio/mpeg"}
    data["itunes_duration"] = itunes_duration if itunes_duration
    @feed.entries.create!(
      title: "Episode",
      url: "http://example.com/ep",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex,
      data: data
    )
  end

  # itunes:duration is optional and plenty of feeds omit it. Returning 0 rather
  # than nil made the presenter's nil guard dead code, so the reader was told
  # the episode is "0 minutes" long -- wrong rather than missing.
  test "audio_duration is nil when the feed gave no duration" do
    assert_nil episode.audio_duration
  end

  test "audio_duration still parses a duration the feed did give" do
    assert_equal 3661, episode("1:01:01").audio_duration
  end

  test "a durationless episode renders no duration" do
    entry = episode
    presenter = EntryPresenter.new(entry, nil, ApplicationController.new.view_context)

    assert_nil presenter.audio_duration
  end

  test "an episode with a duration still renders one" do
    entry = episode("10:00")
    presenter = EntryPresenter.new(entry, nil, ApplicationController.new.view_context)

    assert_equal "10 minutes", presenter.audio_duration
  end

  test "queueing a durationless episode stores a duration the column allows" do
    entry = episode
    entry.send(:mark_as_unplayed)

    queued = QueuedEntry.where(entry_id: entry.id).first
    assert queued, "the episode was not queued"
    assert_equal 0, queued.duration
  end
end
