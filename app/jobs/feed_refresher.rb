class FeedRefresher
  include BatchJobs
  include Sidekiq::Worker

  attr_accessor :force_refresh

  def perform(batch, priority_refresh, force_refresh = false)
    @force_refresh = force_refresh
    feed_ids = build_ids(batch)
    count = priority_refresh ? 1 : 0
    jobs = build_arguments(feed_ids, count)
    if jobs.present?
      Sidekiq::Client.push_bulk(
        "args" => jobs,
        "class" => "FeedRefresherFetcher",
        "queue" => "feed_refresher_fetcher",
        "retry" => false,
      )
    end
  end

  def build_arguments(feed_ids, count)
    fields = [:id, :feed_url, :etag, :last_modified, :subscriptions_count, :push_expiration]
    subscriptions = Subscription.where(feed_id: feed_ids, active: true, muted: false).group(:feed_id).count
    feeds = Feed.xml.where(id: feed_ids, active: true).where("subscriptions_count > ?", count).pluck(*fields)
    feeds.each_with_object([]) do |result, array|
      feed = Hash[fields.zip(result)]
      if subscriptions.key?(feed[:id])
        array << Arguments.new(feed, url_template, force_refresh).to_a
      end
    end
  end

  def url_template
    @url_template ||= begin
      template = nil
      if ENV["PUSH_URL"]
        uri = URI(ENV["PUSH_URL"])
        id = 454545
        template = Rails.application.routes.url_helpers.push_feed_url(Feed.new(id: id), protocol: uri.scheme, host: uri.host)
        template = template.sub(id.to_s, "%d")
      end
      template
    end
  end

  def _debug(feed_id)
    Sidekiq::Client.push_bulk(
      "args" => build_arguments([feed_id], 0),
      "class" => "FeedRefresherFetcher",
      "queue" => "feed_refresher_fetcher_debug",
      "retry" => false,
    )
  end

  class Arguments
    def initialize(feed, push_url, force_refresh = false)
      @feed = feed
      @push_url = push_url
      @body = nil # only needed when receiving PuSH
      @force_refresh = force_refresh
    end

    def to_a
      options = {
        etag: etag,
        last_modified: last_modified,
        subscriptions_count: @feed[:subscriptions_count],
        push_callback: push_callback,
        hub_secret: hub_secret,
        push_mode: push_mode,
        record_status: @force_refresh,
      }
      [@feed[:id], @feed[:feed_url], options]
    end

    private

    def etag
      @force_refresh ? nil : @feed[:etag]
    end

    def last_modified
      @force_refresh ? nil : @feed[:last_modified]
    end

    def push_callback
      push? ? @push_url % @feed[:id] : nil
    end

    def hub_secret
      push? ? Push.hub_secret(@feed[:id]) : nil
    end

    def push_mode
      push? ? "subscribe" : nil
    end

    def push?
      @push ||= @push_url && @feed[:push_expiration].nil? || @feed[:push_expiration] < Time.now
    end
  end
end
