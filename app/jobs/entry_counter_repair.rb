# Recomputes the counter caches on `entries` for a list of entry ids.
#
# StarredEntry, RecentlyPlayedEntry and QueuedEntry each declare
# `belongs_to :entry, counter_cache: true`, so Rails maintains these columns
# on create and destroy -- but not through a bulk delete or a bulk insert,
# which skip callbacks entirely. Every caller that reaches for `delete_all`
# or `import` on those tables owes the affected entries a repair.
#
# It matters because EntryDeleter#prune_entries reads these columns to decide
# what may be removed: a count left above zero pins its entry in place
# forever, and one left below zero would let a still-referenced entry be
# deleted.
#
# Recompute, not decrement: recompute is idempotent, so a Sidekiq retry is
# free and a concurrent star, play or queue on the same entry cannot make the
# count drift.
class EntryCounterRepair
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  # Keeps the Sidekiq argument payload small. 2_000 bigints is about 16KB.
  CHUNK = 2_000

  # `count(*)` never returns NULL, so every column lands on 0 rather than
  # NULL when nothing remains. That matters for
  # recently_played_entries_count, which is nullable and which prune_entries
  # compares with `= 0`.
  REPAIR_SQL = <<~SQL
    starred_entries_count = (
      SELECT count(*) FROM starred_entries WHERE starred_entries.entry_id = entries.id
    ),
    recently_played_entries_count = (
      SELECT count(*) FROM recently_played_entries WHERE recently_played_entries.entry_id = entries.id
    ),
    queued_entries_count = (
      SELECT count(*) FROM queued_entries WHERE queued_entries.entry_id = entries.id
    )
  SQL

  def perform(entry_ids)
    return if entry_ids.blank?

    Entry.where(id: entry_ids).update_all(REPAIR_SQL)
  end

  # Enqueues repairs for a set of entry ids, in payload-sized chunks.
  #
  # Sidekiq imposes no limit on argument size -- it validates only that
  # arguments are JSON-native types -- so CHUNK is chosen against its
  # guidance to keep arguments small. Measured on Sidekiq 8.0.10, a job
  # carrying 2,000 entry ids serializes to about 22KB.
  def self.enqueue(entry_ids)
    Array(entry_ids).uniq.each_slice(CHUNK) { |chunk| perform_async(chunk) }
  end

  # Repairs every entry in a set of feeds.
  #
  # The fallback for callers holding too many entry ids to carry. Feeds are a
  # far smaller handle than entries, but a coarser one: this repairs every
  # entry in the feed, not just the ones that changed. Prefer `enqueue` with
  # exact ids wherever the count is bounded.
  #
  # A job rather than an inline loop, because the walk is unbounded -- the
  # caller should not be made to wait on it.
  class ForFeeds
    include Sidekiq::Worker
    sidekiq_options queue: :utility

    def perform(feed_ids)
      return if feed_ids.blank?

      Entry.where(feed_id: feed_ids).select(:id).in_batches(of: CHUNK) do |batch|
        EntryCounterRepair.perform_async(batch.pluck(:id))
      end
    end

    def self.enqueue(feed_ids)
      Array(feed_ids).uniq.each_slice(CHUNK) { |chunk| perform_async(chunk) }
    end
  end
end
