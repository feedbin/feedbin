require_relative '../../lib/batch_jobs'
class EntryBulkIndex
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(batch = nil, schedule = false)
    if schedule
      build
    else
      index(batch)
    end
  end

  def index(batch)
    ids = build_ids(batch)
    entries = Entry.where(id: ids)
    Tire.index("entries").import(entries)
  end

  def build
    jobs = job_args(1160152813)
    Sidekiq::Client.push_bulk(
      'args'  => jobs,
      'class' => "EntryBulkIndex",
      'queue' => 'worker_slow'
    )
  end

end
