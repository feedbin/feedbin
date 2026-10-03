# Moves each legacy original value into compressed_original_content and
# clears the legacy column. One job for each range of ids: production ids are sparse
# (about 2.6% in use), so the range is larger than SidekiqHelper::BATCH_SIZE.
# Entry ignores the original column, so this job selects it by name.
#
# Each build is a pass. Two Redis counters track it, because a full-table
# count of the legacy rows cannot finish under production's statement
# timeout: a pass is done when no jobs are pending, and a done pass that
# found no legacy rows proves the backfill is complete.
class BackfillOriginalContent
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  BATCH_SIZE = 100_000
  PENDING_KEY = "backfill_original_content:pending"
  FOUND_KEY = "backfill_original_content:found"
  COUNTER_TTL = 30.days.to_i

  def self.progress
    pending, found = Sidekiq.redis { |redis| [redis.get(PENDING_KEY), redis.get(FOUND_KEY)] }
    {pending: pending.to_i, found: found.to_i}
  end

  def perform(batch)
    first = (batch - 1) * BATCH_SIZE + 1
    found = 0
    Entry.where(id: first..(first + BATCH_SIZE - 1)).where.not(original: nil)
      .select(:id, :content, :original, :updated_at)
      .find_each(batch_size: 500) do |entry|
        convert(entry)
        found += 1
      end
    Sidekiq.redis do |redis|
      redis.incrby(FOUND_KEY, found)
      redis.decr(PENDING_KEY)
    end
  end

  # The updated_at condition skips a row the crawler changed after the read.
  # That row keeps its legacy original, and the next pass converts it. The
  # legacy value replaces any temporary original EntryUpdate wrote meanwhile.
  # update_all skips callbacks and leaves updated_at as it is.
  def convert(entry)
    compressed = OriginalContent.compress(entry.original&.dig("content"), base: entry.content)
    Entry.where(id: entry.id, updated_at: entry.updated_at)
      .update_all(compressed_original_content: compressed, original: nil)
  end

  # Starts a pass: resets both counters, then queues every range, newest
  # first, because recently updated entries are the ones people read.
  def build
    batches = (Entry.maximum(:id) / BATCH_SIZE.to_f).ceil
    Sidekiq.redis do |redis|
      redis.set(PENDING_KEY, batches)
      redis.set(FOUND_KEY, 0)
      redis.expire(PENDING_KEY, COUNTER_TTL)
      redis.expire(FOUND_KEY, COUNTER_TTL)
    end
    Sidekiq::Client.push_bulk(
      "args" => batches.downto(1).map { [it] },
      "class" => self.class
    )
  end
end
