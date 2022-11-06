module Search
  class Client
    def self.request(method, path, options = {})
      unless path.start_with?("/")
        path = "/#{path}"
      end
      $elasticsearch[:pool].with do |connection|
        connection.headers(content_type: "application/json").request(method.to_sym, path, options).parse
      end
    end

    def self.index(index_name, id:, document:)
      Search::Client.request(:put, [index_name, "_doc", id].join("/"), json: document)
    end

    def self.delete(index_name, id:)
      Search::Client.request(:delete, [index_name, "_doc", id].join("/"))
    end

    def self.bulk(records)
      options = {
        body: prepare_bulk_request(records),
        params: {"filter_path" => "took"}
      }
      Search::Client.request(:post, "_bulk", options)
    end

    def self.validate(index_name, query:)
      result = Search::Client.request(:get, [index_name, "_validate", "query"].join("/"), json: query)
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
      Search::Client.request(:get, [Action.table_name, "_search"].join("/"), json: query)
    end

    private

    def self.prepare_bulk_request(records)
      records.map(&:to_request).join("\n") + "\n"
    end
  end
end