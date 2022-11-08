module Search
  class Client
    PATHS = {
      document: "/%{index}/_doc/%{id}",
      search:   "/%{index}/_search",
      validate: "/%{index}/_validate/query",
      msearch:  "/%{index}/_msearch",
      count:    "/%{index}/_count",
      refresh:  "/_refresh",
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

    def self.search(index, query:, page: 1, per_page: WillPaginate.per_page)
      params = {
        from: page == 1 ? 0 : (page.to_i - 1) * per_page,
        size: per_page
      }

      path = PATHS[:search] % {index:}
      response = Search::Client.request(:get, path, json: query, params: params)

      total = response.dig("hits", "total", "value") || 0
      ids = response.dig("hits", "hits")&.map {|hit| hit.dig("_id") } || []
      pagination = Array.new(total).paginate(page: page)

      OpenStruct.new({total:, ids:, pagination:})
    end

    def self.get(index, id:)
      path = PATHS[:document] % {index:, id:}
      Search::Client.request(:get, path)
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

    def self.msearch(index, records:)
      options = {
        body: prepare_bulk_request(records)
      }
      path = PATHS[:msearch] % {index:}
      Search::Client.request(:post, path, options)
    end

    def self.validate(index, query:)
      path = PATHS[:validate] % {index:}
      result = Search::Client.request(:get, path, json: query)
      result.dig("valid")
    end

    def self.count(index)
      path = PATHS[:count] % {index:}
      result = Search::Client.request(:get, path)
      result.dig("count")
    end

    def self.refresh
      Search::Client.request(:post, PATHS[:refresh])
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