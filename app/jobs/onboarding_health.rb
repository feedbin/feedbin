class OnboardingHealth
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform
    unhealthy_feeds = []

    Feedbin::Application.config.onboarding_feeds.each do |onboarding_feed|
      feed = Feed.find_by(feed_url: onboarding_feed[:feed_url])
      next unless feed

      if feed.crawl_data.error_count > 5
        unhealthy_feeds << {
          title: onboarding_feed[:title],
          feed_url: onboarding_feed[:feed_url],
          error_count: feed.crawl_data.error_count
        }
      end
    end

    if unhealthy_feeds.any? && ENV["ADMIN_EMAIL"].present?
      UserMailer.onboarding_health_alert(unhealthy_feeds).deliver
    end
  end
end
