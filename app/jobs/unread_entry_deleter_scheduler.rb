class UnreadEntryDeleterScheduler
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform
    User.select(:id).find_in_batches(batch_size: 10_000) do |users|
      Sidekiq::Client.push_bulk(
        'args'  => users.map{ |user| user.attributes.values },
        'class' => 'UnreadEntryDeleter',
        'queue' => 'worker_slow',
        'retry' => false
      )
    end
  end

end
