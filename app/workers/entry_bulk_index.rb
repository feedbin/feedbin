require_relative '../../lib/batch_jobs'
class EntryBulkIndex
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  Client = $alt_search ? $alt_search : Entry.__elasticsearch__.client

  def perform(batch = nil, schedule = false, last_entry_id = nil)
    if schedule
      build(last_entry_id)
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
      Client.bulk(
        index: Entry.index_name,
        type: Entry.document_type,
        body: data
      )
    end
  end

  def build(last_entry_id)
    jobs = job_args(last_entry_id)
    Sidekiq::Client.push_bulk(
      'args'  => jobs,
      'class' => "EntryBulkIndex",
      'queue' => 'worker_slow'
    )
  end

end
