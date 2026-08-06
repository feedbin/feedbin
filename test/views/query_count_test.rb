require "test_helper"

# Each of these asserts that a render's query count does not grow with the
# number of rows it renders. They compare two sizes rather than a fixed number
# so the request's constant cost does not have to be encoded in the test.
class QueryCountTest < ActionController::TestCase
  tests ActionsController

  setup do
    @user = users(:ben)
    @feeds = create_feeds(@user)
  end

  def matching(statements, pattern)
    statements.select { _1.match?(pattern) }
  end

  test "the actions list does not look the owner up once per action" do
    login_as @user
    @user.actions.create!(feed_ids: [@feeds.first.id], actions: ["mark_read"])

    with_one = capture_sql { get :index }
    4.times { @user.actions.create!(feed_ids: [@feeds.first.id], actions: ["mark_read"]) }
    with_five = capture_sql { get :index }

    assert_response :success
    pattern = /FROM "users" WHERE "users"\."id"/i
    assert_equal matching(with_one, pattern).count, matching(with_five, pattern).count,
      "the owner is re-fetched per action row"
  end

  test "the add-feed results panel builds its feed stats once" do
    statements = capture_sql do
      ApplicationController.render(
        Dialog::AddFeed::ResultsData.new(
          query: "example",
          feeds: @feeds,
          tag_editor: TagEditor.new(taggings: TagEditor.taggings(@user), user: @user, feed: nil),
          search: true,
          basic_auth: false,
          auth_attempted: false,
          subscriptions: []
        ),
        layout: nil
      )
    end

    assert @feeds.length > 1, "needs more than one result to be meaningful"
    assert_equal 1, matching(statements, /feed_stats/i).count
  end

  test "the import report does not re-query the suggestions it preloaded" do
    with_one = capture_sql { render_import_report(1) }
    with_five = capture_sql { render_import_report(5) }

    pattern = /FROM "discovered_feeds"/i
    assert_equal matching(with_one, pattern).count, matching(with_five, pattern).count,
      "the preloaded suggestions are re-queried per fixable item"
  end

  private

  def render_import_report(count)
    prefix = SecureRandom.hex(4)
    import = @user.imports.new(filename: "subscriptions.opml")
    items = count.times.map { |index|
      import.import_items.new(status: :fixable, details: {
        title: "Example #{index}",
        xml_url: "http://#{prefix}-#{index}.example.com/feed.xml",
        html_url: "http://#{prefix}-#{index}.example.com/"
      })
    }
    import.save!
    # The report only renders its fixable list once the import has finished.
    import.update_column(:complete, true)
    items.each_with_index do |item, index|
      DiscoveredFeed.create!(site_url: item.site_url, feed_url: "http://#{prefix}-#{index}.example.com/alternative.xml")
    end
    ApplicationController.render(Settings::Imports::StatusComponent.new(import: import.reload), layout: nil)
  end
end
