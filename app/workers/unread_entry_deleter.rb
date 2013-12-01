class UnreadEntryDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow, retry: false

  def perform(user_id)
    user = User.find(user_id)
    if user.keep_unread_entries.nil?
      user.unread_entries.where("published < :two_months", {two_months: 2.months.ago}).delete_all
    end
  end

end