class Onboarding::SubscriptionsController < ApplicationController
  def update
    feed_urls = params[:feed_url] || {}

    selected_urls = feed_urls.select { |url, value| value != "0" }.keys
    deselected_urls = feed_urls.select { |url, value| value == "0" }.keys

    selected_urls.each do |feed_url|
      feed = Feed.where(feed_url: feed_url).take || find_feed(feed_url)
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

  # import_mode makes FeedFinder re-raise instead of swallowing, so one slow or
  # broken host would otherwise 500 the first screen a new account sees — and
  # take the rest of the selection down with it, since the loop is not
  # transactional. Skip the url that failed and keep going.
  def find_feed(feed_url)
    FeedFinder.feeds(feed_url, import_mode: true)&.first
  rescue Feedkit::Error
    nil
  rescue => exception
    ErrorService.notify(exception)
    nil
  end
end
