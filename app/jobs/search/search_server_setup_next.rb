module Search
  class SearchServerSetupNext
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
          document: SearchDataV2.new(entry).to_h
        )
      end
      Search::Client.bulk(records) unless records.empty?
    end

    def build
      jobs = job_args(Entry.last.id)
      Sidekiq::Client.push_bulk(
        "args" => jobs,
        "class" => self.class
      )
    end
  end
end