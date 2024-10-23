class FeedSearch
  def initialize(query)
    @query = query
  end

  def search
    query = {
      query: {
        function_score: {
          query: {
            simple_query_string: {
              query: @query,
              fields: ["title^2", "site_url", "feed_url", "description", "meta_title", "author"],
              default_operator: "and"
            }
          },
          field_value_factor: {
            field: "subscriptions_count",
            factor: 0.1,
          },
          boost_mode: "sum"
        }
      }
    }
    response = Search.client { _1.search(Feed.table_name, query: query, per_page: 3) }
    response.records(Feed)
  end
end
