module Search
  class Connection
    PATHS = {
      document: "/%{index}/_doc/%{id}",
      search:   "/%{index}/_search",
      validate: "/%{index}/_validate/query",
      msearch:  "/%{index}/_msearch",
      count:    "/%{index}/_count",
      refresh:  "/_refresh",
      bulk:     "/_bulk",
      aliases:  "/_aliases",
      alias:    "/_alias/%{name}",
      pit:       "/%{index}/_pit",
      pit_close: "/_pit",
      # A point-in-time search names its index in the body, not the path.
      pit_search: "/_search",
    }

    # Long enough to walk a large match set, short enough that an abandoned
    # cursor releases its segments promptly.
    PIT_KEEP_ALIVE = "2m"

    # Elasticsearch rejects a from + size above index.max_result_window, so
    # there is no point honouring a larger page than this.
    MAX_PER_PAGE = 1_000

    # How many hits all_matches walks at a time.
    ALL_MATCHES_PER_PAGE = 1_000

    def initialize(url, username: nil, password: nil)
      @url = url
      @username = username
      @password = password
    end

    def search(index, query:, page: 1, per_page: WillPaginate.per_page)
      # Both arrive straight from the query string on most paths, so coerce
      # here rather than relying on every caller to have done it.
      page = page.to_i.clamp(1, Float::INFINITY).to_i
      per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)

      path = PATHS[:search] % {index:}
      data = request(:get, path, json: query, params: {
        :_source => false,
        :from    => (page - 1) * per_page,
        :size    => per_page
      })
      Response.new(data, page: page, per_page: per_page)
    end

    def index(index, id:, document:)
      path = PATHS[:document] % {index:, id:}
      request(:put, path, json: document)
    end

    def get(index, id:)
      path = PATHS[:document] % {index:, id:}
      request(:get, path)
    end

    def delete(index, id:)
      path = PATHS[:document] % {index:, id:}
      request(:delete, path)
    end

    def bulk(records)
      options = {
        body: prepare_bulk_request(records),
        params: {"filter_path" => "took"}
      }
      request(:post, PATHS[:bulk], options)
    end

    def msearch(index, records:)
      options = {
        body: prepare_bulk_request(records)
      }
      path = PATHS[:msearch] % {index:}
      request(:post, path, options).safe_dig("responses")&.map do |data|
        Response.new(data)
      end
    end

    def validate(index, query:)
      path = PATHS[:validate] % {index:}
      result = request(:get, path, json: query)
      result.safe_dig("valid")
    end

    def count(index)
      path = PATHS[:count] % {index:}
      result = request(:get, path)
      result.safe_dig("count")
    end

    def refresh
      request(:post, PATHS[:refresh])
    end

    def delete_index(index)
      request(:delete, "/#{index}")
    end

    # Walks the whole match set with search_after rather than from/size.
    #
    # Paginating could not do this job. The page count came from the reported
    # total, which Elasticsearch caps at track_total_hits and reports as fact,
    # so anything past the cap was dropped with no indication it had stopped
    # early -- and past index.max_result_window from/size would have been
    # rejected outright. search_after has neither ceiling.
    def all_matches(index, query:)
      pit_id = open_pit(index)

      # _shard_doc is the tiebreaker a point-in-time provides, so this needs
      # nothing from the index's own mapping -- the entries and actions
      # indexes do not share a sortable field.
      body = query.deep_dup.except(:from, "from", :sort, "sort").merge(
        pit: {id: pit_id, keep_alive: PIT_KEEP_ALIVE},
        sort: [{_shard_doc: "asc"}],
        size: ALL_MATCHES_PER_PAGE,
        track_total_hits: false
      )

      ids = []
      loop do
        data = request(:get, PATHS[:pit_search], json: body, params: {:_source => false})
        hits = data.safe_dig("hits", "hits") || []
        break if hits.empty?

        ids.concat hits.map { _1["_id"].to_i }
        break if hits.length < ALL_MATCHES_PER_PAGE

        # The pit id can be rotated between requests.
        body = body.merge(
          pit: {id: data["pit_id"] || pit_id, keep_alive: PIT_KEEP_ALIVE},
          search_after: hits.last["sort"]
        )
      end
      ids
    ensure
      close_pit(pit_id) if pit_id
    end

    def open_pit(index)
      path = PATHS[:pit] % {index:}
      request(:post, path, params: {keep_alive: PIT_KEEP_ALIVE})["id"]
    end

    def close_pit(pit_id)
      request(:delete, PATHS[:pit_close], json: {id: pit_id})
    rescue
      # The keep_alive expires on its own; a failure to close is not worth
      # replacing the caller's result with an exception.
    end

    def add_alias(index, alias_name:)
      data = {
        actions: [{
          add: {
            index: index,
            alias: alias_name
          }
        }]
      }
      request(:post, PATHS[:aliases], json: data)
    end

    def get_indexes_from_alias(alias_name)
      path = PATHS[:alias] % {name: alias_name}
      response = request(:get, path)
      if response.key?("error") && response.safe_dig("status") == 404
        []
      else
        response.keys
      end
    end

    def update_alias(alias_name:, old_indexes:, new_index:)
      actions = old_indexes.map do |old_index|
        {
          remove: { index: old_index, alias: alias_name }
        }
      end
      actions.push({
        add: { index: new_index, alias: alias_name }
      })
      request(:post, PATHS[:aliases], json: { actions: actions })
    end

    def reindex(index, mappings:, &block)
      new_index = "#{index}-#{Time.now.to_i}"
      request(:put, new_index, json: mappings)
      begin
        yield(new_index)
      rescue => exception
        delete_index(new_index)
        raise
      end
      old_indexes = get_indexes_from_alias(index)
      update_alias(alias_name: index, old_indexes: old_indexes, new_index: new_index)
      old_indexes.each { delete_index(_1) }
    end

    def request(method, path, options = {})
      unless path.start_with?("/")
        path = "/#{path}"
      end
      connection.request(method.to_sym, path, **options).parse
    end

    def close
      Rails.logger.info("Closing search connection")
      connection.close
    end

    private

    def connection
      @connection ||= begin
        client = HTTP
          .use(instrumentation: { instrumenter: ActiveSupport::Notifications.instrumenter, namespace: "search" })
          .persistent(@url)
          .headers(content_type: "application/json")
        client = client.basic_auth(user: @username, pass: @password) if @username && @password
        client
      end
    end

    def prepare_bulk_request(records)
      records.map(&:to_request).join("\n") + "\n"
    end
  end
end
