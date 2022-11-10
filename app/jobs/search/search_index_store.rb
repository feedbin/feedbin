module Search
  class SearchIndexStore
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    def perform(klass, id, update = false)
      entry = Entry.find(id)
      document = entry.search_data
      index(entry, document)
      percolate(entry, document, update)
    rescue ActiveRecord::RecordNotFound
    end

    def index(entry, document)
      Search::Client.index(Entry.table_name, id: entry.id, document: document)
    end

    def percolate(entry, document, update)
      return if update
      query = {
        :_source => false,
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  {
                    term: {feed_id: entry.feed_id}
                  },
                  {
                    percolate: {
                      field: "query",
                      document: document
                    }
                  }
                ]
              }
            }
          }
        }
      }

      ids = Search::Client.all_matches(Action.table_name, query: query)
      if ids.present?
        ActionsPerform.perform_async(entry.id, ids, update)
      end
    end
  end
end