require "test_helper"

class HarvestEmbedsTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @user = users(:ben)
    @entry = create_entry(@user.feeds.first)
  end

  test "should harvest from iframe" do
    @entry.update(content: %(<iframe src="http://www.youtube.com/embed/video_id"></iframe>))

    assert_difference -> { Sidekiq.redis {|r| r.scard(HarvestEmbeds::SET_NAME) } }, +1 do
      HarvestEmbeds.new.perform(@entry.id)
    end

  end

  test "should harvest from youtube feed" do
    @entry.update(data: {youtube_video_id: "video_id"})

    assert_difference -> { Sidekiq.redis {|r| r.scard(HarvestEmbeds::SET_NAME) } }, +1 do
      HarvestEmbeds.new.perform(@entry.id)
    end
  end

end
