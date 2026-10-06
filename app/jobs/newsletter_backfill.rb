# Writes every newsletter page to B2. The page is rebuilt from entry.content,
# so the old bucket is never read. Safe to run again: a put overwrites the same
# key with the same body.
#
#   NewsletterBackfill.new.build
#   NewsletterBackfill.progress  # => {pending: 0, saved: 123, mismatched: 0}
#
# A pass is done at pending: 0. mismatched counts entries whose url is on
# NEWSLETTER_HOST but is not the page URL; the CDN cutover breaks those. Sidekiq supplies the parallelism: one job for
# each feed, and a feed holds a few hundred entries at most.
class NewsletterBackfill
  include Sidekiq::Worker
  sidekiq_options queue: :backfill

  COUNTERS = %w[pending saved mismatched].freeze
  TTL = 30.days.to_i

  def self.key(name)
    "newsletter_backfill:#{name}"
  end

  def self.progress
    values = Sidekiq.redis { |redis| COUNTERS.map { |name| redis.get(key(name)) } }
    COUNTERS.map(&:to_sym).zip(values.map(&:to_i)).to_h
  end

  # A second build while jobs are still out would reset the counters under
  # them, and their decrements would end the new pass early.
  def build(force: false)
    pending = self.class.progress[:pending]
    raise "A pass is still running (pending: #{pending}). Use build(force: true) to start over." if pending > 0 && !force
    ids = Feed.newsletter.pluck(:id)
    Sidekiq.redis do |redis|
      COUNTERS.each { |name| redis.set(self.class.key(name), 0, ex: TTL) }
      redis.set(self.class.key("pending"), ids.size, ex: TTL)
    end
    Sidekiq::Client.push_bulk("class" => self.class, "args" => ids.zip) if ids.any?
  end

  # Every entry gets a page, including one with no content: the saver always
  # wrote one, so skipping it would turn a blank page into a 404.
  def perform(feed_id)
    saved = mismatched = 0
    Entry.where(feed_id: feed_id).find_in_batches(batch_size: 500) do |entries|
      entries.each do |entry|
        page = NewsletterPage.new(entry)
        page.save
        saved += 1
        mismatched += 1 if mismatched_url?(entry, page)
      end
    end
    finish(saved: saved, mismatched: mismatched)
  end

  private

  # Since 2022 the saver stored NEWSLETTER_HOST plus the S3 response path. The
  # B2 origin serves /<key> only, so a stored path with anything else in it
  # (a bucket name, from path-style access) stops working at the cutover.
  def mismatched_url?(entry, page)
    url = page.url
    return false if url.nil? || entry.url.blank? || entry.url == url
    URI(entry.url).host == URI(url).host
  rescue URI::InvalidURIError
    false
  end

  def finish(saved:, mismatched:)
    Sidekiq.redis do |redis|
      redis.incrby(self.class.key("saved"), saved)
      redis.incrby(self.class.key("mismatched"), mismatched)
      redis.decr(self.class.key("pending"))
    end
  end
end
