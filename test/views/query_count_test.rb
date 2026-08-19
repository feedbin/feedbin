require "test_helper"

module QueryCounting
  def matching(statements, pattern)
    statements.select { it.match?(pattern) }
  end
end

# Each of these asserts that a render's query count does not grow with the
# number of rows it renders. They compare two sizes rather than a fixed number
# so the request's constant cost does not have to be encoded in the test.
class QueryCountTest < ActionController::TestCase
  tests ActionsController
  include QueryCounting

  setup do
    @user = users(:ben)
    @feeds = create_feeds(@user)
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

# Separate class, not a third test on QueryCountTest above: ActionController::TestCase
# binds one controller per class via `tests`, and the sidebar is FeedsController's
# auto_update, not ActionsController's.
class SidebarQueryCountTest < ActionController::TestCase
  tests FeedsController
  include QueryCounting

  setup do
    @user = users(:ben)
  end

  # FaviconComponent reads @feed.icon_url, which queries icon_image_record;
  # the untagged and tagged sidebar sections both need the preload.
  # subscriptions_hash: "stale" forces the full list partial to render.
  test "the sidebar does not query images once per feed" do
    login_as @user

    with_few = capture_sql { get :auto_update, params: {subscriptions_hash: "stale"}, xhr: true }
    create_feeds(@user, 10)
    with_many = capture_sql { get :auto_update, params: {subscriptions_hash: "stale"}, xhr: true }

    assert_response :success
    pattern = /FROM "images"/i
    assert_equal matching(with_few, pattern).count, matching(with_many, pattern).count,
      "the sidebar's images lookup scales with the feed count"
  end

  # These feeds have a real channel_id, so the preload's grouped lookup has
  # to actually match rows and its count stay flat.
  test "the sidebar does not query the channel avatar once per youtube feed" do
    login_as @user
    subscribe_to_channels(1)

    with_few = capture_sql { get :auto_update, params: {subscriptions_hash: "stale"}, xhr: true }
    subscribe_to_channels(10)
    with_many = capture_sql { get :auto_update, params: {subscriptions_hash: "stale"}, xhr: true }

    assert_response :success
    pattern = /FROM "images"/i
    assert_operator matching(with_many, pattern).count, :>, 0
    assert_equal matching(with_few, pattern).count, matching(with_many, pattern).count,
      "the sidebar's images lookup scales with the youtube feed count"
  end

  def subscribe_to_channels(count)
    count.times.map do
      id = "UC#{SecureRandom.hex(8)}"
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}")
      @user.subscriptions.where(feed: feed).first_or_create
      feed
    end
  end
end

# Its own class for the same reason SidebarQueryCountTest is: ActionController::TestCase
# binds one controller per class via `tests`.
#
# ?mode=extended is the documented way clients ask for images, and the endpoint
# serves up to 100 entries. _entry_extended.json.jbuilder reaches
# preview_image_record twice per entry -- through processed_image? and through
# preview_image_data -- so a dropped preload is 100 queries a request.
class ApiEntriesQueryCountTest < ApiControllerTestCase
  tests Api::V2::EntriesController
  include QueryCounting

  setup do
    @user = users(:new)
    @feed = create_feeds(@user).first
  end

  def seed_preview_images(entries)
    entries.each do |entry|
      url = "http://example.com/#{entry.id}.jpg"
      Image.create!(
        provider: :entry_preview, provider_id: entry.id.to_s, feed_id: @feed.id,
        url: url, variant: "542x304",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: Image.storage_path_for(url, "542x304"),
        width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc",
        data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/#{entry.id}.jpg"}
      )
    end
  end

  test "the extended entries feed does not query images once per entry" do
    login_as @user
    seed_preview_images(bulk_create_entries(@feed, 1))

    with_one = capture_sql { get :index, params: {mode: "extended"}, format: :json }
    seed_preview_images(bulk_create_entries(@feed, 4))
    with_five = capture_sql { get :index, params: {mode: "extended"}, format: :json }

    assert_response :success
    pattern = /FROM "images"/i
    assert_operator matching(with_five, pattern).count, :>, 0
    assert_equal matching(with_one, pattern).count, matching(with_five, pattern).count,
      "the extended entries payload's images lookup scales with the entry count"
  end
end

# Dialog::ActionResults renders entries/_entry per result, and that partial
# reaches processed_image? on every entry and link_image on the tweet ones.
class ActionResultsQueryCountTest < ActiveSupport::TestCase
  include QueryCounting

  setup do
    clear_search
    flush_redis
    @user = users(:ben)
    @feed = @user.feeds.first
  end

  def seed_image(entry, provider)
    url = "http://example.com/#{provider}-#{entry.id}.jpg"
    Image.create!(
      provider: provider, provider_id: entry.id.to_s, feed_id: @feed.id,
      url: url, variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for(url, "542x304"),
      width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc",
      data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/#{provider}-#{entry.id}.jpg"}
    )
  end

  # A micropost with a link preview, which is the only shape of entry whose
  # render reaches link_image. _entry only takes that branch when the entry is
  # a tweet or micropost whose link_preview? is true, and link_preview? still
  # gates on the legacy twitter_link_image_processed -- link_image then prefers
  # the row over it.
  def create_link_preview_entry
    entry = create_entry(@feed)
    entry.update!(
      title: nil,
      data: entry.data.merge(
        "author" => {"name" => "Example", "_microblog" => {"username" => "example"}},
        "urls" => ["https://example.com/p"],
        "saved_pages" => {"https://example.com/p" => {"result" => {"title" => "Example page"}}},
        "twitter_link_image_processed" => "https://bucket.s3.amazonaws.com/abc/link-legacy.jpg"
      )
    )
    entry
  end

  # One plain entry with a preview image and one micropost with a link image,
  # so both associations are on the page. Indexed and refreshed because
  # Action#results is an Elasticsearch query.
  def index_pair
    plain = create_entry(@feed)
    seed_image(plain, :entry_preview)

    linked = create_link_preview_entry
    seed_image(linked, :entry_link_preview)
    assert linked.micropost&.link_preview?, "the render must reach link_image for this test to mean anything"

    [plain, linked].each { Search::SearchIndexStore.new.perform("Entry", it.id) }
    Search.client { it.refresh }
  end

  def render_results
    action = @user.actions.create!(feed_ids: [@feed.id], actions: ["mark_read"])
    # ActionsController, not ApplicationController: the dialog renders
    # actions/_text_description, which only resolves under that prefix.
    ActionsController.render(Dialog::ActionResults.new(action: action), layout: nil)
  end

  test "the action results dialog does not query images once per entry" do
    index_pair
    with_two = capture_sql { render_results }

    2.times { index_pair }
    with_six = capture_sql { render_results }

    pattern = /FROM "images"/i
    assert_operator matching(with_six, pattern).count, :>, 0
    assert_equal matching(with_two, pattern).count, matching(with_six, pattern).count,
      "the action results dialog's images lookup scales with the result count"
  end
end
