# Writes every newsletter page to B2. The page is rebuilt from entry.content,
# so the old bucket is never read. Safe to run again: a put overwrites the same
# key with the same body.
#
#   NewsletterBackfill.new.build
#   NewsletterBackfill.progress  # => {pending: 0, saved: 123, skipped: 0}
#
# A pass is done at pending: 0. Sidekiq supplies the parallelism: one job for
# each feed, and a feed holds a few hundred entries at most.
class NewsletterBackfill
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  COUNTERS = %w[pending saved skipped].freeze
  TTL = 30.days.to_i

  def self.key(name)
    "newsletter_backfill:#{name}"
  end

  def self.progress
    values = Sidekiq.redis { |redis| COUNTERS.map { |name| redis.get(key(name)) } }
    COUNTERS.map(&:to_sym).zip(values.map(&:to_i)).to_h
  end

  def build
    ids = Feed.newsletter.pluck(:id)
    Sidekiq.redis do |redis|
      COUNTERS.each { |name| redis.set(self.class.key(name), 0, ex: TTL) }
      redis.set(self.class.key("pending"), ids.size, ex: TTL)
    end
    Sidekiq::Client.push_bulk("class" => self.class, "args" => ids.zip) if ids.any?
  end

  def perform(feed_id)
    saved = skipped = 0
    Entry.where(feed_id: feed_id).find_in_batches(batch_size: 500) do |entries|
      entries.each do |entry|
        if entry.content.nil?
          skipped += 1
        else
          NewsletterPage.new(entry).save
          saved += 1
        end
      end
    end
    finish(saved: saved, skipped: skipped)
  end

  private

  def finish(saved:, skipped:)
    Sidekiq.redis do |redis|
      redis.incrby(self.class.key("saved"), saved)
      redis.incrby(self.class.key("skipped"), skipped)
      redis.decr(self.class.key("pending"))
    end
  end
end
