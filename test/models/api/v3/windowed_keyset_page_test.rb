require "test_helper"

# A windowed page is the plain newest-first page, found by reading less. Every
# test here builds both and holds them to the same rows, order, more? and
# next cursor.
class Api::V3::WindowedKeysetPageTest < ActiveSupport::TestCase
  LIMITS = [1, 2, 3, 7, 50, 1000].freeze

  setup do
    freeze_time
    @user = users(:new)
    @now = Time.current

    busy = subscribe(feed("busy"))
    second = subscribe(feed("second"))
    bursts = subscribe(feed("bursts"))
    old = subscribe(feed("old"))
    subscribe(feed("empty"))
    other = feed("other")

    # Ties within a feed and across feeds, clusters apart in time, an entry
    # ahead of the clock, and entries older than any window reaches.
    entries busy, [@now + 1.hour, @now - 5.minutes, @now - 10.minutes, *[@now - 1.hour] * 4, *[@now - 2.hours] * 3]
    entries second, [*[@now - 1.hour] * 2, @now - 3.hours, *[@now - 1.day] * 2, @now - 1.day - 1.second, @now - 26.hours, @now - 30.hours]
    entries bursts, [*[@now - 10.days] * 3, @now - 10.days - 1.minute, @now - 11.days, @now - 12.days, *[@now - 100.days] * 4, *[@now - 900.days] * 3]
    entries old, [*[@now - 3.years] * 2, @now - 3.years - 1.day, @now - 6.years, @now - 6.years]
    entries other, [@now - 1.hour, @now - 1.hour, @now - 10.days, @now - 3.years]
  end

  test "every page of the timeline is the plain page, at every page size" do
    expected = Entry.where(feed_id: feeds).sort_by { [_1.created_at, _1.id] }.reverse.map(&:id)
    assert_equal 36, expected.size

    LIMITS.each do |limit|
      pages = walk(limit) { windowed(_1, limit) }

      assert_equal walk(limit) { plain(_1, limit) }, pages, "limit #{limit}"
      assert_equal expected, pages.flat_map { _1[:ids] }, "limit #{limit}"
    end
  end

  test "a page from any cursor is the plain page, a cursor inside a tie included" do
    positions = Entry.all.map { [_1.created_at, _1.id] }
    positions += [[@now + 1.year, 0], [@now, 0], [@now - 1.hour, 0], [@now - 1.hour, Entry.maximum(:id) + 1], [@now - 2.years, 0], [@now - 10.years, 0]]

    positions.each do |time, id|
      cursor = {"sort" => "received_desc", "timestamp" => (time.to_r * 1_000_000).to_i, "id" => id}
      [1, 3, 1000].each do |limit|
        assert_equal summary(plain(cursor, limit)), summary(windowed(cursor, limit)), "from #{time.iso8601(6)}/#{id}, limit #{limit}"
      end
    end
  end

  test "accounts with no feeds, one empty feed and one feed" do
    @user.subscriptions.delete_all
    assert_equal walk(2) { plain(_1, 2) }, walk(2) { windowed(_1, 2) }
    assert_equal [], windowed(nil, 2).records

    only = subscribe(feed("only"))
    assert_equal [], windowed(nil, 2).records
    assert_not windowed(nil, 2).more?

    entries only, [@now - 1.minute, @now - 1.minute, @now - 40.days, @now - 5.years]
    [1, 2, 3, 4, 5].each do |limit|
      assert_equal walk(limit) { plain(_1, limit) }, walk(limit) { windowed(_1, limit) }, "limit #{limit}"
    end
  end

  test "an account with thousands of feeds" do
    @user.subscriptions.delete_all
    stamp = {created_at: @now, updated_at: @now}
    ids = Feed.insert_all!(2_000.times.map { {feed_url: "https://many.example.com/#{_1}", title: "Feed #{_1}", **stamp} }, returning: :id).rows.flatten
    Subscription.insert_all!(ids.map { {user_id: @user.id, feed_id: _1, **stamp} })
    # Every third feed is empty; the rest hold a recent entry, one tied with
    # every other feed's, and an old one.
    rows = ids.each_with_index.reject { |_, index| index % 3 == 0 }.flat_map do |id, index|
      [@now - (index % 97).minutes, @now - 3.days, @now - (200 + index % 900).days].map { entry_row(id, _1) }
    end
    Entry.insert_all!(rows)

    [400, 1000].each do |limit|
      pages = walk(limit) { windowed(_1, limit) }

      assert_equal walk(limit) { plain(_1, limit) }, pages, "limit #{limit}"
      assert_equal rows.size, pages.sum { _1[:ids].size }
    end
  end

  test "composes with a filter on the entries" do
    tied = Entry.where(feed_id: feeds, created_at: @now - 1.hour).order(:id).pluck(:id)
    filters = {
      "without some of a tie" => Entry.where.not(id: tied.values_at(0, 3, 5)),
      "after a time" => Entry.where("entries.created_at > ?", @now - 11.days),
      "a subquery" => Entry.where(id: Entry.where("entries.id % 2 = 0").select(:id)),
      "nothing" => Entry.none
    }

    filters.each do |name, scope|
      [1, 3, 1000].each do |limit|
        assert_equal walk(limit) { plain(_1, limit, scope: scope) }, walk(limit) { windowed(_1, limit, scope: scope) }, "#{name}, limit #{limit}"
      end
    end
  end

  test "keeps what the scope preloads" do
    page = windowed(nil, 3, scope: Entry.preload(:feed))

    assert_equal 3, page.records.size
    assert page.records.all? { _1.association(:feed).loaded? }
  end

  test "a window that holds a page is all that is read" do
    statements = queries { windowed(nil, 2).records }

    assert statements.any? { _1.include?("LATERAL") }
    assert statements.none? { plain?(_1) }, statements.join("\n")
  end

  test "the plain query is the last resort, when no window holds a page" do
    # Eight entries are older than this, six of them inside the widest window.
    cursor = {"sort" => "received_desc", "timestamp" => ((@now - 2.years).to_r * 1_000_000).to_i, "id" => 0}
    expected = summary(plain(cursor, 7))
    statements = queries { assert_equal expected, summary(windowed(cursor, 7)) }
    assert_equal 7, expected[:ids].size

    assert statements.any? { _1.include?("LATERAL") }
    assert_equal 1, statements.count { plain?(_1) }, statements.join("\n")
  end

  test "a window that turns out not to hold a page is not trusted" do
    page = windowed(nil, 5)
    # As if the rows the probe counted were gone by the time they were read.
    page.stub(:window, @now - 7.minutes) do
      assert_equal summary(plain(nil, 5)), summary(page)
    end
  end

  test "is only for a newest-first page" do
    assert_raises(ArgumentError) do
      Api::V3::WindowedKeysetPage.new(Entry.all, feeds: feeds, sort: "received_asc", column: :created_at, direction: :asc, limit: 2, key: "timestamp")
    end
  end

  private

  def feed(name)
    Feed.create!(feed_url: "https://#{name}.example.com/feed", host: "#{name}.example.com", title: name, site_url: "https://#{name}.example.com")
  end

  def subscribe(feed)
    @user.subscriptions.create!(feed: feed)
    feed
  end

  # Rows without callbacks: only where they sit in time is under test.
  def entries(feed, times)
    Entry.insert_all!(times.map { entry_row(feed.id, _1) })
  end

  def entry_row(feed_id, time)
    {feed_id: feed_id, public_id: SecureRandom.hex, title: "Entry", content: "<p>Words</p>", published: time, created_at: time, updated_at: time}
  end

  def feeds
    @user.subscriptions.select(:feed_id)
  end

  def options(cursor, limit)
    {sort: "received_desc", column: :created_at, direction: :desc, limit: limit, cursor: cursor, key: "timestamp"}
  end

  def plain(cursor, limit, scope: Entry.all)
    Api::V3::KeysetPage.new(scope.where(feed_id: feeds), **options(cursor, limit))
  end

  def windowed(cursor, limit, scope: Entry.all)
    Api::V3::WindowedKeysetPage.new(scope, feeds: feeds, **options(cursor, limit))
  end

  def summary(page)
    {ids: page.records.map(&:id), more: page.more?, next_cursor: page.next_cursor}
  end

  # Every page from the first to the last, each asked for with the cursor the
  # one before it gave.
  def walk(limit)
    pages = []
    cursor = nil
    loop do
      pages << summary(yield(cursor))
      break unless pages.last[:more]
      raise "the timeline does not end" if pages.size > 100
      cursor = Api::V3::Cursor.decode(pages.last[:next_cursor])
    end
    pages
  end

  def queries
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] if payload[:sql].include?(%("entries")) && payload[:name] != "SCHEMA"
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def plain?(sql)
    sql.include?('"entries"."feed_id" IN (SELECT') && !sql.include?("LATERAL")
  end
end
