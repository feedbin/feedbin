class BigBatchScheduler
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform
    total_records = 180_000_000
    batch_size = 1000
    batch_count = (total_records.to_f/batch_size.to_f).ceil
    1.upto(batch_count) do |batch|
      BigBatch.perform_async(batch)
    end
  end

end