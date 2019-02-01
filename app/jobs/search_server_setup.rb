class SearchServerSetup
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  Client = $search[:alt] || $search[:main]

  def perform(batch = nil, schedule = false, last_entry_id = nil)
    if schedule
      build(last_entry_id)
      touch_actions
    else
      index(batch)
    end
  end

  def index(batch)
    ids = build_ids(batch)
    data = Entry.where(id: ids).map { |entry|
      {
        index: {
          _id: entry.id,
          data: entry.as_indexed_json,
        },
      }
    }
    if data.present?
      Client.bulk(
        index: Entry.index_name,
        type: Entry.document_type,
        body: data,
      )
    end
  end

  def build(last_entry_id)
    jobs = job_args(last_entry_id)
    Sidekiq::Client.push_bulk(
      "args" => jobs,
      "class" => self.class.name,
      "queue" => self.class.get_sidekiq_options["queue"].to_s,
    )
  end

  def touch_actions
    Action.find_each do |action|
      action.touch
    rescue
      nil
    end
  end
end
