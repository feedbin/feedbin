module Search
  class Client
    PATHS = {
      search:   "/%{index}/_search",
      document: "/%{index}/_doc/%{id}",
      validate: "/%{index}/_validate/query",
      bulk:     "/_bulk",
    }

    def self.request(method, path, options = {})
      unless path.start_with?("/")
        path = "/#{path}"
      end
      $elasticsearch[:pool].with do |connection|
        connection.headers(content_type: "application/json").request(method.to_sym, path, options).parse
      end
    end

    def self.search(index, query:)
      path = PATHS[:search] % {index:}
      Search::Client.request(:get, path, json: query)
    end

    def self.index(index, id:, document:)
      path = PATHS[:document] % {index:, id:}
      Search::Client.request(:put, path, json: document)
    end

    def self.delete(index, id:)
      path = PATHS[:document] % {index:, id:}
      Search::Client.request(:delete, path)
    end

    def self.bulk(records)
      options = {
        body: prepare_bulk_request(records),
        params: {"filter_path" => "took"}
      }
      Search::Client.request(:post, PATHS[:bulk], options)
    end

    def self.validate(index, query:)
      path = PATHS[:validate] % {index:}
      result = Search::Client.request(:get, path, json: query)
      result.dig("valid")
    end

    def self.percolate(feed_id, document:)
      query = {
        :_source => false,
        query: {
          constant_score: {
            filter: {
              bool: {
                must: [
                  {term: {feed_id: feed_id}},
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

      path = PATHS[:search] % {index: Action.table_name}
      Search::Client.request(:get, path, json: query)
    end

    private

    def self.prepare_bulk_request(records)
      records.map(&:to_request).join("\n") + "\n"
    end
  end
end