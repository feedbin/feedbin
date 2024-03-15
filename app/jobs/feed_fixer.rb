class FeedFixer
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  def perform(feed_id, force = false)
    @feed = Feed.find(feed_id)

    return unless @feed.fixable_error?

    if !force && recent_discovery_exists?
      Sidekiq.logger.info "Skipping discovery, already checked recently feed=#{@feed.id} url=#{@feed.feed_url}"
      return
    end

    @feed.update(site_url: @feed.site_url)

    clear_discoveries

    urls = begin
      FeedFinder.new(@feed.site_url).find_options
    rescue
      []
    end

    existing = @feed.subscriptions.where.not(fix_status: Subscription.fix_statuses[:none])
    hosts = Set.new
    urls.each do |url|
      next unless option = validate_option(url)

      discovery = DiscoveredFeed.find_or_create_by(
        site_url: @feed.site_url,
        feed_url: option.feed_url
      )

      discovery.update(
        title: option.title,
        verified_at: Time.now
      )

      subscriptions = @feed.subscriptions.fix_suggestion_none

      new_subscriptions = subscriptions - existing
      new_subscriptions.map { _1.user.setting_on!(:fix_feeds_available) }

      subscriptions.update_all(
        fix_status: Subscription.fix_statuses[:present],
        updated_at: Time.now
      )

      hosts.add(discovery.host)
    end

    hosts.each { FaviconCrawler::Finder.perform_async(_1) }
  end

  def clear_discoveries
    DiscoveredFeed.where(site_url: @feed.site_url).destroy_all
    @feed.subscriptions
      .where.not(fix_status: Subscription.fix_statuses[:ignored])
      .update_all(fix_status: Subscription.fix_statuses[:none], updated_at: Time.now)
  end

  def recent_discovery_exists?
    DiscoveredFeed.where(
      site_url: @feed.site_url,
      verified_at: 1.week.ago..
    ).exists?
  end

  def validate_option(url)
    result = Feedkit::Request.download(url).parse
    option = Feed.create_with(result.to_feed).new

    valid_entries = result.entries.find do |parsed|
      option.entries.create_with(parsed.to_entry).new.valid?
    end

    option if option.valid? && valid_entries.present?
  rescue
    false
  end

  def build
    return unless feed = Feed.last
    batches = job_args(feed.id)
    batches.each do |(batch)|
      feed_ids = build_ids(batch)

      active = Subscription.select(:feed_id)
        .where(feed_id: feed_ids, active: true)
        .distinct
        .pluck(:feed_id)

      jobs = Feed.xml
        .where(id: active)
        .select { _1.fixable_error? }
        .map { [_1.id] }

        Sidekiq::Client.push_bulk(
          "args" => jobs,
          "class" => self.class
        )
    end
  end
end
