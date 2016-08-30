require_relative '../../lib/batch_jobs'

class UnreadEntryDeleter
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow, retry: false

  def perform(user_id = nil, schedule = false)
    if schedule
      build
    else
      delete(user_id)
    end
  end

  private

  def delete(user_id)
    user = User.find(user_id)
    if user.keep_unread_entries.nil?
      user.unread_entries.where("published < :two_months", {two_months: 2.months.ago}).delete_all
    end
  end

  def build
    enqueue_all(User, self.class)
  end

end