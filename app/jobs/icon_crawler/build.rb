module IconCrawler
  class Build
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(feed_id)
      feed = Feed.find(feed_id)
      if feed.twitter_user?
        Provider::Twitter.new.perform(feed.twitter_user.screen_name, feed.twitter_user.profile_image_uri_https(:original))
      elsif feed.youtube_channel?
        Provider::Youtube.new.perform(feed.youtube_channel_id)
      end

      Provider::Favicon.new.perform(feed.host)
    end
  end
end