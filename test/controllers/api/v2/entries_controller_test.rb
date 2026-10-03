require "test_helper"

class Api::V2::EntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should get specific ids" do
    login_as @user
    entries = @entries.sample(2)
    ids = entries.map(&:id).join(",")
    get :index, params: {ids: ids}, format: :json

    assert_response :success
    assert_equal_ids(entries, parse_json)
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    assert_equal @entries.length, assigns(:entries).length
  end

  test "should show entry" do
    login_as @user
    entry = @entries.first

    get :show, params: {id: entry}, format: :json
    assert_response :success

    result = parse_json
    assert_has_keys(entry_keys, result)
  end

  test "should show entry with all keys" do
    login_as @user
    entry = @entries.first

    get :show, params: {id: entry, include_content_diff: "true", include_enclosure: "true", include_original: "true"}, format: :json
    assert_response :success

    result = parse_json
    assert_has_keys(entry_keys(true), result)
  end

  test "should get text format" do
    login_as @user
    get :text, params: {id: @entries.first}, format: :json
    assert_response :success
  end

  test "should get starred entries" do
    login_as @user
    entries = @entries.sample(2)

    entries.each do |entry|
      StarredEntry.create_from_owners(@user, entry)
    end

    get :index, params: {starred: "true"}, format: :json
    assert_response :success
    assert_equal_ids(entries, parse_json)
  end

  test "should get entries since date" do
    login_as @user
    entry = @entries.sample
    date = entry.created_at.iso8601(6)
    get :index, params: {since: date}, format: :json

    expected = Entry.where("created_at > :time", {time: entry.created_at})
    assert_equal_ids expected, parse_json
  end

  test "should accept a minute-precision since" do
    login_as @user
    since = 10.years.ago.utc.strftime("%Y-%m-%dT%H:%MZ")

    get :index, params: {since: since}, format: :json

    assert_response :success
    assert_equal_ids @entries, parse_json
  end

  test "should accept a date-only since" do
    login_as @user
    since = 10.years.ago.utc.strftime("%Y-%m-%d")

    get :index, params: {since: since}, format: :json

    assert_response :success
    assert_equal_ids @entries, parse_json
  end

  test "should filter on a since it cannot drop silently" do
    login_as @user
    since = 1.day.from_now.utc.strftime("%Y-%m-%dT%H:%MZ")

    get :index, params: {since: since}, format: :json

    assert_response :success
    assert_equal [], parse_json, "a since the API accepts has to actually filter"
  end

  test "should say which parameter is wrong when per_page is zero" do
    login_as @user

    get :index, params: {per_page: "0"}, format: :json

    assert_response :bad_request
    assert parse_json["errors"].any? { |error| error.key?("per_page") }, parse_json.inspect
  end

  test "should say which parameter is wrong when per_page is not a number" do
    login_as @user

    get :index, params: {per_page: "lots"}, format: :json

    assert_response :bad_request
    assert parse_json["errors"].any? { |error| error.key?("per_page") }, parse_json.inspect
  end

  test "should cap an unreasonably large per_page rather than honouring it" do
    login_as @user

    get :index, params: {per_page: "1000000"}, format: :json

    assert_response :success
    assert_equal Api::V2::ApiController::MAX_PER_PAGE, assigns(:page_query).per_page
  end

  test "should say which parameter is wrong when since cannot be parsed" do
    login_as @user

    get :index, params: {since: "yesterday"}, format: :json

    assert_response :bad_request
    assert parse_json["errors"].any? { |error| error.key?("since") }, parse_json.inspect
  end

  test "original keeps its keys and formats" do
    login_as @user
    entry = @entries.first
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))

    get :show, params: {id: entry, include_original: "true"}, format: :json
    assert_response :success

    original = parse_json["original"]
    assert_equal %w[author content title url entry_id published data fingerprint], original.keys
    assert_equal "<p>Old text.</p>", original["content"]
    assert_equal entry.title, original["title"]
    assert_equal entry.url, original["url"]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/, original["published"])
  end

  test "original is null without one" do
    login_as @user

    get :show, params: {id: @entries.first, include_original: "true"}, format: :json
    assert_response :success

    result = parse_json
    assert result.key?("original")
    assert_nil result["original"]
  end

  test "extended mode returns the same original" do
    login_as @user
    entry = @entries.first
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))

    get :show, params: {id: entry, mode: "extended"}, format: :json
    assert_response :success

    assert_equal "<p>Old text.</p>", parse_json.dig("original", "content")
  end

  private

  def entry_keys(all = false)
    keys = %w[id feed_id title author summary created_at published url content]
    if all
      keys = keys.concat(%w[content_diff enclosure original])
    end
    keys
  end
end
