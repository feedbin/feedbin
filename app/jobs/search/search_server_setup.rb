module Search
  class SearchServerSetup
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: :utility

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
            data: entry.search_data
          }
        }
      }
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
        "args" => jobs,
        "class" => self.class
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
end