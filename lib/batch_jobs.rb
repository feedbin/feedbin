module BatchJobs
  BATCH_SIZE = 5_000

  def job_args(total_records, *args)
    batch_count = (total_records.to_f/BATCH_SIZE.to_f).ceil
    jobs = []
    1.upto(batch_count) do |batch|
      jobs.push([batch].concat(args))
    end
    jobs
  end

  def build_ids(batch)
    start = ((batch - 1) * BATCH_SIZE) + 1
    finish = batch * BATCH_SIZE
    (start..finish).to_a
  end

  def enqueue_all(klass, sidekiq_class)
    if last_id = klass.last&.id
      defaults = {
        'class' => sidekiq_class.name.freeze,
        'queue' => sidekiq_class.get_sidekiq_options["queue"].to_s.freeze,
        'retry' => sidekiq_class.get_sidekiq_options["retry"].freeze,
      }
      (1..last_id).to_a.each_slice(10_000) do |group|
        Sidekiq::Client.push_bulk(
          defaults.merge('args' => group.map { |id| [id] })
        )
      end
    end
  end
end