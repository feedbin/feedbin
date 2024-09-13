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
      user.queued_entries.where(entry: entries).delete_all
    end
  end
end
