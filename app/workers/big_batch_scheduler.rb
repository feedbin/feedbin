class BigBatchScheduler
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform
    batch_size = 1000
    start = (813083561/batch_size).floor
    finish = (814728487/batch_size).ceil
    jobs = []
    start.upto(finish) do |batch|
      jobs.push([batch])
    end
    Sidekiq::Client.push_bulk(
      'args'  => jobs,
      'class' => 'BigBatch',
      'queue' => 'worker_slow'
    )
  end

end
