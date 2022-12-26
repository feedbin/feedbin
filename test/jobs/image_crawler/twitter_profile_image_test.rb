require "test_helper"

module ImageCrawler
  class TwitterProfileImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
      user = load_tweet("one").deep_symbolize_keys[:user]
      @twitter_user = TwitterUser.create!(data: user, screen_name: user[:screen_name])
    end

    test "should enqueue Find" do
      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        TwitterProfileImage.new.perform(@twitter_user.id)
      end
      assert_equal("https://pbs.twimg.com/profile_images/946448045415256064/bmEy3r8A.jpg", Pipeline::Find.jobs.first["args"].last.first)
    end
  end
end