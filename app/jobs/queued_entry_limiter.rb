class QueuedEntryLimiter
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find(user_id)
    limit = user.podcast_download_limit

    queued_entries = user.queued_entries.group_by(&:feed_id).transform_values do |entries|
      entries.map(&:entry_id)
    end

    queued_entries.each do |feed_id, entry_ids|
      entries = Entry.where(id: entry_ids).order(published: :desc).offset(limit)
      over_limit = user.queued_entries.where(entry: entries)
      # Read the ids before the delete: delete_all skips the counter cache
      # queued_entries maintains on entries, and reports nothing about what
      # it removed.
      removed = over_limit.pluck(:entry_id)
      over_limit.delete_all
      EntryCounterRepair.enqueue(removed)
    end
  end
end
