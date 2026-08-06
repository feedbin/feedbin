require "test_helper"

module Search
  class ConnectionTest < ActiveSupport::TestCase
    setup do
      clear_search
      @user = users(:ben)
      @feed = @user.feeds.first
      @index = Search.index_name(Entry.table_name)
      @token = "slice10token"
    end

    # Elasticsearch stops counting hits at track_total_hits and reports the cap
    # as the total. all_matches derived its page count from that number, so a
    # search matching more than the cap silently returned only the first N ids
    # -- which is why "mark all search results as read" left the rest unread.
    test "all_matches returns every id when the reported total is capped" do
      entries = 25.times.map { create_entry(@feed).tap { _1.update!(title: "#{@token} #{SecureRandom.hex}") } }
      entries.each { SearchIndexStore.new.perform("Entry", _1.id) }
      Search.client { _1.refresh }

      query = {
        track_total_hits: 10,
        query: {term: {"title" => @token}},
        sort: [{published: "desc"}]
      }

      ids = Search::Connection.stub_const(:ALL_MATCHES_PER_PAGE, 10) do
        Search.client { _1.all_matches(@index, query: query) }
      end

      assert_equal entries.map(&:id).sort, ids.sort
    end

    # The actions index stores percolator queries with none of the entries
    # index's sortable fields, so the cursor cannot depend on the mapping.
    test "all_matches walks more than one page of the actions index" do
      actions = Sidekiq::Testing.inline! do
        12.times.map { @user.actions.create!(feed_ids: [@feed.id], actions: ["mark_read"]) }
      end
      Search.client { _1.refresh }

      ids = Search::Connection.stub_const(:ALL_MATCHES_PER_PAGE, 5) do
        Search.client { _1.all_matches(Search.index_name(Action.table_name), query: {query: {match_all: {}}}) }
      end

      assert_equal actions.map(&:id).sort, ids.sort
    end

    test "all_matches returns an empty list when nothing matches" do
      query = {query: {term: {"title" => "nothingmatchesthis"}}}

      assert_equal [], Search.client { _1.all_matches(@index, query: query) }
    end

    # A proxy error page or empty reply arrives with no Content-Type header,
    # which .parse reported as only "Unknown MIME type:" -- no status, no body,
    # nothing to say what actually answered. Keep the evidence in the message.
    test "request surfaces status and body when the response cannot be parsed" do
      stub_request(:get, "http://search.example.com/entries/_count")
        .to_return(status: 503, body: "<html>upstream timeout</html>", headers: {})

      connection = Search::Connection.new("http://search.example.com")

      exception = assert_raises(Search::Connection::ResponseError) do
        connection.request(:get, "/entries/_count")
      end

      assert_includes exception.message, "503"
      assert_includes exception.message, "upstream timeout"
      assert_kind_of HTTP::Error, exception.cause
    end
  end
end
