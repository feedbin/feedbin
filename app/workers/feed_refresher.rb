require_relative '../../lib/batch_jobs'

class FeedRefresher
  include BatchJobs
  include Sidekiq::Worker

  def perform(batch, priority_refresh)
    feed_ids = build_ids(batch)
    count = priority_refresh ? 1 : 0
    fields = [:id, :feed_url, :etag, :last_modified, :subscriptions_count, :push_expiration]
    results = Feed.where(id: feed_ids).where("subscriptions_count > ?", count).pluck(*fields)
    subscriptions = Subscription.where(feed_id: feed_ids, active: true, muted: false).group(:feed_id).count

    arguments = results.each_with_object([]) do |result, array|
      feed = Hash[fields.zip(result)]
      if subscriptions.has_key?(feed[:id])
        array << Arguments.new(feed, url_template).to_a
      end
    end

    Sidekiq::Client.push_bulk(
      'args'  => arguments,
      'class' => 'FeedRefresherFetcher',
      'queue' => 'feed_refresher_fetcher',
      'retry' => false
    )
  end

  def url_template
    @url_template ||= begin
      template = nil
      if ENV['PUSH_URL']
        uri = URI(ENV['PUSH_URL'])
        id = 454545
        template = Rails.application.routes.url_helpers.push_feed_url(Feed.new(id: id), protocol: uri.scheme, host: uri.host)
        template = template.sub(id.to_s, "%d")
      end
      template
    end
  end

  class Arguments
    def initialize(feed, push_url)
      @feed = feed
      @push_url = push_url
      @body = nil # only needed when receiving PuSH
    end

    def to_a
      [@feed[:id], @feed[:feed_url], @feed[:etag], @feed[:last_modified], @feed[:subscriptions_count], @body, push_callback, hub_secret]
    end

    private

    def push_callback
      (push?) ? @push_url % @feed[:id] : nil
    end

    def hub_secret
      (push?) ? Push::hub_secret(@feed[:id]) : nil
    end

    def push?
      @push ||= @push_url && @feed[:push_expiration].nil? || @feed[:push_expiration] < Time.now
    end

  end

end