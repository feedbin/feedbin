class MigrateUnreads
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(user_id)
    user = User.find(user_id)
    UnreadEntry.transaction do
      unread_ids = user.unread_entries.lock(true).pluck(:entry_id)
      entry_ids = Entry.where(id: unread_ids).pluck(:id)
      unread_entries = user.unread_entries.where(entry_id: entry_ids).map(&:attributes)
      Unread.import unread_entries, on_duplicate_key_ignore: true
    end
  rescue ActiveRecord::RecordNotFound
  end

  def build
    enqueue_all(User, self.class)
  end

end
