class Onboarding::SubscriptionsController < ApplicationController
  def update
    feed_urls = params[:feed_url] || {}

    selected_urls = feed_urls.select { |url, value| value != "0" }.keys
    deselected_urls = feed_urls.select { |url, value| value == "0" }.keys

    feeds = Feed.where(feed_url: feed_urls.keys)
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

    head :ok
  end
end
