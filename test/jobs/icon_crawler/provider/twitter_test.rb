require "test_helper"

module IconCrawler
  module Provider
    class TwitterTest < ActiveSupport::TestCase
      setup do
        flush_redis
        twitter_user = load_tweet("one").deep_symbolize_keys[:user]
        @feed = Feed.first
        @feed.update(options: {twitter_user: twitter_user})
      end

      test "should schedule image job" do
        Twitter.new.perform(@feed.twitter_user.screen_name, @feed.twitter_user.profile_image_uri_https(:original))
        image = ImageCrawler::Image.new(ImageCrawler::Pipeline::Find.jobs.first["args"].first)

        assert_equal("JeffBenjam", image.icon_provider_id)
        assert_equal(0, image.icon_provider)
        assert_equal(["https://pbs.twimg.com/profile_images/946448045415256064/bmEy3r8A.jpg"], image.image_urls)
      end

      test "should create icon records" do
        profile_url = "https://pbs.twimg.com/profile_images/946448045415256064/bmEy3r8A.jpg"
        provider_id = @feed.twitter_user.screen_name
        stub_request_file("image.png", profile_url)

        stub_request(:put, /s3\.amazonaws\.com/)
          .to_return(status: 200)

        assert_difference -> {Icon.count}, +1 do
          assert_difference -> {RemoteFile.count}, +1 do
            Sidekiq::Testing.inline! do
              Twitter.new.perform(provider_id, @feed.twitter_user.profile_image_uri_https(:original))
            end
          end
        end

        assert_not_nil(RemoteFile.find_by(original_url: profile_url))
        assert_equal(profile_url, Icon.provider_twitter.find_by_provider_id(provider_id).url)
      end
    end
  end
end