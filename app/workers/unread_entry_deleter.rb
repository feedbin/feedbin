class UnreadEntryDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform
    UnreadEntry.where("published < :two_months", {two_months: 2.months.ago}).delete_all
  end

end