class BigBatchScheduler
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform
    total_records = 872963011
    batch_size = 1000
    batch_count = (total_records.to_f/batch_size.to_f).ceil
    jobs = []
    1.upto(batch_count) do |batch|
      jobs.push([batch])
    end
    Sidekiq::Client.push_bulk(
      'args'  => jobs,
      'class' => 'BigBatch',
      'queue' => 'worker_slow'
    )
  end

end