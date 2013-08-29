class StarredCountScheduler
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform
    StarredEntry.select(:id, :entry_id).find_in_batches(batch_size: 10_000) do |entries|
      Sidekiq::Client.push_bulk(
        'args'  => entries.map{ |entry| [entry.entry_id] },
        'class' => 'StarredCount',
        'queue' => 'worker_slow',
        'retry' => false
      )
    end
  end

end
