module Search
  class SearchServerSetup
    include Sidekiq::Worker
    include SidekiqHelper
    sidekiq_options queue: :utility

    def perform(batch)
      ids = build_ids(batch)
      records = Entry.where(id: ids).map do |entry|
        Search::BulkRecord.new(
          action: :index,
          index: Entry.table_name,
          id: entry.id,
          document: entry.search_data
        )
      end
      $search[:main].with { _1.bulk(records) } unless records.empty?
    end

    def build
      jobs = job_args(Entry.last.id)
      Sidekiq::Client.push_bulk(
        "args" => jobs,
        "class" => self.class
      )
      touch_actions
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