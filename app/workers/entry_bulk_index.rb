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
    data = Entry.where(id: ids).map do |entry|
      {
        index: {
          _id: entry.id,
          data: entry.as_indexed_json
        }
      }
    end
    if data.present?
      Entry.__elasticsearch__.client.bulk(
        index: Entry.index_name,
        type: Entry.document_type,
        body: data
      )
    end
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
