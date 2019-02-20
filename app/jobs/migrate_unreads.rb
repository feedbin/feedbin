class MigrateUnreads
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(user_id)
    UnreadEntry.transaction do
      user = User.find(user_id)
      unreads = user.unread_entries.lock(true).map(&:attributes)
      Unread.import unreads, on_duplicate_key_ignore: true
    end
  end

  def build
    enqueue_all(User, self.class)
  end

end
