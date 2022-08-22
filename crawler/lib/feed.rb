# frozen_string_literal: true

class Feed
  extend Forwardable

  def_delegators :http_cache, :etag, :last_modified, :checksum, :save
  def_delegators :feed_status, :ok?, :log_download!, :downloaded_at

  def_delegator :feed_status, :count, :attempt_count
  def_delegator :feed_status, :error!, :download_error
  def_delegator :redirect_cache, :read, :redirect

  attr_accessor :redirects

  def initialize(feed_id)
    @feed_id = feed_id
    @redirects = []
  end

  def next_attempt
    Time.at(feed_status.next_retry).utc.iso8601
  end

  def download_success
    feed_status.clear! unless last_error && last_error["class"] == "Feedkit::NotFeed"
    redirect_cache.save(redirects)
  end

  def last_error
    feed_status.attempt_log.first
  end

  def redirect_cache
    @redirect_cache ||= RedirectCache.new(@feed_id)
  end

  def feed_status
    @feed_status ||= FeedStatus.new(@feed_id)
  end

  def http_cache
    @http_cache ||= HTTPCache.new(@feed_id)
  end

  def inspect
    "#<#{self.class}:#{object_id.to_s(16)} @feed_id=#{@feed_id} next_attempt=#{next_attempt} redirect=#{redirect.inspect} http_cache=#{http_cache.cached} last_error=#{last_error.inspect}>"
  end
end
