require "test_helper"

class SearchableCountTest < ActiveSupport::TestCase
  setup do
    clear_search
    @user = users(:ben)
  end

  # build_query re-reads the user's whole unread, starred and subscription id
  # lists on every call, and saved_search_count calls it once per saved search.
  # The sidebar polls this endpoint, so the cost is paid interactively.
  test "counting saved searches reads each id list once" do
    5.times { |index| @user.saved_searches.create!(name: "S#{index}", query: "example") }

    statements = capture_sql { Entry.saved_search_count(@user) }

    {
      unreads: /FROM "#{UnreadEntry.table_name}"/i,
      starred: /FROM "starred_entries"/i,
      subscriptions: /FROM "subscriptions"/i
    }.each do |name, pattern|
      assert_operator statements.count { _1.match?(pattern) }, :<=, 1,
        "#{name} was read once per saved search"
    end
  end

  test "Action#results does not re-run its search for every reader" do
    feed = @user.feeds.first
    action = @user.actions.create!(feed_ids: [feed.id], query: "example", actions: ["mark_read"])

    calls = 0
    original = Search::Connection.instance_method(:search)
    Search::Connection.define_method(:search) do |*args, **kwargs|
      calls += 1
      original.bind(self).call(*args, **kwargs)
    end

    results = action.results
    results.total
    results.records
    action.results.total

    assert_equal 1, calls
  ensure
    Search::Connection.define_method(:search, original) if original
  end
end
