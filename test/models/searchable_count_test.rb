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

  # The cap was a switch, not a limit: at 49 saved searches every badge had a
  # count and at 50 they all silently went blank, with a 200 and no message.
  test "crossing the saved search cap still returns counts" do
    50.times { |index| @user.saved_searches.create!(name: "S#{index}", query: "example") }

    counts = Entry.saved_search_count(@user.reload)

    assert counts.present?, "every saved search badge went blank at the cap"
  end

  test "counting embeds the unread id list once, not once per saved search" do
    feed = @user.feeds.first
    entry = create_entry(feed).tap { _1.update!(title: "countpayload #{SecureRandom.hex}") }
    Search::SearchIndexStore.new.perform("Entry", entry.id)
    mark_unread(@user)
    Search.client { _1.refresh }

    searches = 3.times.map { |index| @user.saved_searches.create!(name: "S#{index}", query: "countpayload") }

    requests = []
    original = Search::Connection.instance_method(:request)
    Search::Connection.define_method(:request) do |method, path, options = {}|
      requests << [method, path, options]
      original.bind(self).call(method, path, options)
    end

    counts = Entry.saved_search_count(@user.reload)

    searches.each do |search|
      assert_equal [entry.id], counts[search.id]
    end

    payload = JSON.dump(requests.map(&:last))
    occurrences = payload.scan(/.{0,60}(?<!\d)#{entry.id}(?!\d).{0,20}/)
    assert_equal 1, occurrences.length,
      "the unread entry id should appear exactly once in the request payload, contexts: #{occurrences.inspect}"
  ensure
    Search::Connection.define_method(:request, original) if original
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
