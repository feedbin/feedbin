class EntryDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  # An entry pinned by a star or a play is never pruned, so a feed accumulates
  # them without limit and the delete set can be millions of rows by the time
  # something unpins them. Slicing bounds the per-round work -- the IN list
  # handed to delete_entries and the Sidekiq payloads -- by SLICE rather than
  # by the feed's backlog. 1_000 matches the slice delete_entries already uses
  # for ImageGarbageCollector.
  #
  # A batch that raises aborts the job. The Sidekiq retry starts the prune
  # over, but batches that already deleted are gone, so the retry resumes at
  # the failed batch rather than repeating finished work, and the daily
  # EntryDeleterScheduler pass is the backstop.
  SLICE = 1_000

  def perform(feed_id)
    feed = Feed.find(feed_id)

    feed.feed_stats.where("day < ?", 90.days.ago).delete_all
    prune_entries(feed_id, entry_limit(feed)) if prunable?(feed)
    UnreadLimiter.new.perform(feed_id)
  end

  def prunable?(feed)
    return false if feed.protected?
    # entry_limit counts only reader subscriptions; Airshow subscriptions live
    # in podcast_subscriptions. queued_entries cascades on entry delete, so
    # pruning a podcast feed would empty a user's queue and Airshow would
    # delete the downloaded audio.
    return false if feed.podcast_subscriptions.exists?
    true
  end

  def entry_limit(feed)
    return ENV["ENTRY_LIMIT"].to_i if ENV["ENTRY_LIMIT"]
    return 400 if feed.subscriptions.where(active: true).exists?
    # A live reader inside the TTL still gets the full window, not the
    # unsubscribed limit.
    return 400 if feed.standalone_request_at&.after?(StandaloneRetention::TTL.ago)
    10
  end

  def prune_entries(feed_id, entry_limit, slice = SLICE)
    entry_count = Entry.where(feed_id: feed_id).count
    return unless entry_count > entry_limit

    # Computed once, outside the loop: the newest entry_limit entries by
    # published date are what the feed keeps, and that set does not change as
    # older entries are removed beneath it.
    entries_to_keep = Entry.where(feed_id: feed_id).order("published DESC").limit(entry_limit).pluck("entries.id")

    # An entry is prunable only when nothing references it. All three counts
    # are counter caches, so they are only as trustworthy as the code that
    # maintains them -- see EntryCounterRepair for the bulk paths that skip
    # them and must enqueue a repair.
    #
    # One scan, not in_batches. in_batches keys each page on `feed_id = ? AND
    # id > ? ORDER BY id`, and no index serves that -- entries carries id only
    # as an INCLUDE payload on the feed_id index, which cannot order -- so
    # every page re-reads and sorts all the feed's remaining matching rows,
    # making the prune quadratic in the feed's entry count. Collecting the ids
    # once costs a list of a few tens of MB for the deepest feed; the way to
    # avoid holding it would be an index on (feed_id, id), which is a migration
    # on a very large table and deliberately out of scope here.
    entry_ids = Entry.where(
      feed_id: feed_id,
      starred_entries_count: 0,
      recently_played_entries_count: 0,
      queued_entries_count: 0
    )
      .where.not(id: entries_to_keep)
      .pluck(:id)

    entry_ids.each_slice(slice) do |batch_ids|
      # The counter filters again, against this batch's primary keys. The id
      # list above is a snapshot, so an entry starred, played or queued while
      # the prune runs is still in it -- re-checking here is what keeps the
      # prune from deleting out from under a user, and queued_entries cascades
      # on entry delete.
      entries_to_delete_ids = Entry.where(
        id: batch_ids,
        starred_entries_count: 0,
        recently_played_entries_count: 0,
        queued_entries_count: 0
      ).pluck(:id)

      delete_entries(feed_id, entries_to_delete_ids)
    end
  end

  def delete_entries(feed_id, entry_ids)
    entry_ids = [*entry_ids]

    if entry_ids.present?
      Search::SearchIndexRemove.perform_async(entry_ids)

      ActiveRecord::Base.transaction do
        UnreadEntry.where(entry_id: entry_ids).delete_all
        UpdatedEntry.where(entry_id: entry_ids).delete_all
        RecentlyReadEntry.where(entry_id: entry_ids).delete_all
        RecentlyPlayedEntry.where(entry_id: entry_ids).delete_all
        StarredEntry.where(entry_id: entry_ids).delete_all
        Entry.where(id: entry_ids).delete_all
      end

      # After the transaction: if the deletes roll back, the usage rows must
      # survive too.
      entry_ids.each_slice(1_000) { ImageGarbageCollector.perform_async(it) }

      Librato.increment("entry.destroy", by: entry_ids.count)
    end
  end
end
