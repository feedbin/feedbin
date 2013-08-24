class StarredCount
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(id)
    Entry.reset_counters(id, :starred_entries)
  end

end
