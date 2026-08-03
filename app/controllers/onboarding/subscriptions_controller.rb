class Onboarding::SubscriptionsController < ApplicationController
  def update
    feed_urls = configured_feed_urls(params[:feed_url])

    selected_urls = feed_urls.select { |url, value| value != "0" }.keys
    deselected_urls = feed_urls.select { |url, value| value == "0" }.keys

    selected_urls.each do |feed_url|
      feed = Feed.where(feed_url: feed_url).take || FeedFinder.feeds(feed_url, import_mode: true)&.first
      @user.subscriptions.find_or_create_by(feed: feed) if feed
    end

    feeds = Feed.where(feed_url: deselected_urls)
    deselected_urls.each do |feed_url|
      feed = feeds.find { it.feed_url == feed_url }
      if feed
        @user.subscriptions.where(feed: feed).destroy_all
      end
    end
  end

  private

  # The onboarding form can only emit the configured feeds, and this action does
  # one synchronous fetch per url it is handed. Without this it accepts any key,
  # any number of them.
  def configured_feed_urls(submitted)
    return {} if submitted.blank?
    allowed = Feedbin::Application.config.onboarding_feeds.map { it[:feed_url] }
    submitted.slice(*allowed)
  end
end
