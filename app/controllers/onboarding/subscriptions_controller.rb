class Onboarding::SubscriptionsController < ApplicationController
  def update
    feed_urls = params[:feed_url] || {}

    selected_urls = feed_urls.select { |url, value| value != "0" }.keys
    deselected_urls = feed_urls.select { |url, value| value == "0" }.keys

    selected_urls.each do |url|
      feed = Feed.find_by(feed_url: url)
      next unless feed
      @user.subscriptions.find_or_create_by(feed: feed)
    end

    deselected_urls.each do |url|
      feed = Feed.find_by(feed_url: url)
      next unless feed
      @user.subscriptions.where(feed: feed).destroy_all
    end

    head :ok
  end
end
