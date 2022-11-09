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

    def self.search(index, query:, page: 1, per_page: WillPaginate.per_page)
      path = PATHS[:search] % {index:}
      data = request(:get, path, json: query, params: {
        from: (page.to_i - 1) * per_page,
        size: per_page
      })
      Response.new(data, page: page, per_page: per_page)
    end

    def self.index(index, id:, document:)
      path = PATHS[:document] % {index:, id:}
      request(:put, path, json: document)
    end

    def self.get(index, id:)
      path = PATHS[:document] % {index:, id:}
      request(:get, path)
    end

    def self.delete(index, id:)
      path = PATHS[:document] % {index:, id:}
      request(:delete, path)
    end

    def self.bulk(records)
      options = {
        body: prepare_bulk_request(records),
        params: {"filter_path" => "took"}
      }
      request(:post, PATHS[:bulk], options)
    end

    def self.msearch(index, records:)
      options = {
        body: prepare_bulk_request(records)
      }
      path = PATHS[:msearch] % {index:}
      request(:post, path, options).dig("responses")&.map do |data|
        Response.new(data)
      end
    end

    def self.validate(index, query:)
      path = PATHS[:validate] % {index:}
      result = request(:get, path, json: query)
      result.dig("valid")
    end

    def self.count(index)
      path = PATHS[:count] % {index:}
      result = request(:get, path)
      result.dig("count")
    end

    def self.percolate(index, query:)
      path = PATHS[:search] % {index: Action.table_name}
      data = request(:get, path, json: query, params: {from: 0, size: 10_000})
      Response.new(data).ids
    end

    def self.all_matches(index, query:)
      callback = proc do |page|
        search(index, query: query, page: page, per_page: 1)
      end
      result = callback.call(1)
      2.upto(result.pagination.total_pages).each_with_object(result.ids) do |page, ids|
        ids.concat callback.call(page).ids
      end
    end

    def self.request(method, path, options = {})
      unless path.start_with?("/")
        path = "/#{path}"
      end
      $elasticsearch[:pool].with do |connection|
        connection.headers(content_type: "application/json").request(method.to_sym, path, options).parse
      end
    end

    def self.refresh
      request(:post, PATHS[:refresh])
    end

    private

    def self.prepare_bulk_request(records)
      records.map(&:to_request).join("\n") + "\n"
    end
  end
end