module BatchJobs
  BATCH_SIZE = 5_000

  def job_args(ending_id, starting_id = 1, *args)
    start_batch = (starting_id.to_f / BATCH_SIZE.to_f).floor
    if start_batch == 0
      start_batch = 1
    end
    end_batch = (ending_id.to_f / BATCH_SIZE.to_f).ceil
    start_batch.upto(end_batch).each_with_object([]) do |batch, jobs|
      jobs.push([batch].concat(args))
    end
  end

  def build_ids(batch)
    start = ((batch - 1) * BATCH_SIZE) + 1
    finish = batch * BATCH_SIZE
    (start..finish).to_a
  end

  def enqueue_all(klass, sidekiq_class)
    if last_id = klass.last&.id
      defaults = {
        "class" => sidekiq_class.name.freeze,
        "queue" => sidekiq_class.get_sidekiq_options["queue"].to_s.freeze,
        "retry" => sidekiq_class.get_sidekiq_options["retry"].freeze,
      }
      (1..last_id).each_slice(10_000) do |slice|
        ids = slice.map { |id| [id] }
        Sidekiq::Client.push_bulk(
          defaults.merge("args" => ids)
        )
      end
    end
  end
end
