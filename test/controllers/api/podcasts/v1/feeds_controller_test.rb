require "test_helper"

class Api::Podcasts::V1::FeedsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @feed.update!(standalone_request_at: Time.now)
  end

  test "should show an xml feed" do
    feed = feeds(:daring_fireball)
    feed.update!(standalone_request_at: Time.now)
    get :show, params: {id: hex_encode(feed.feed_url)}, format: :json
    assert_response :success
    assert_equal feed.id, assigns(:feed).id
  end

  test "should not show a private feed" do
    [:newsletter, :pages].each do |feed_type|
      feed = Feed.create!(
        feed_url: "http://example.com/#{feed_type}?#{SecureRandom.hex}",
        host: "example.com",
        title: feed_type.to_s,
        feed_type: feed_type,
        standalone_request_at: Time.now
      )
      create_entry(feed).update!(content: "SECRET-PRIVATE-BODY")

      # The endpoint falls back to feed discovery when it finds nothing, so the
      # url has to resolve to something that yields no feeds.
      stub_request(:get, feed.feed_url).to_return(status: 404, body: "")

      get :show, params: {id: hex_encode(feed.feed_url)}, format: :json
      assert_response :not_found
      refute_includes @response.body, "SECRET-PRIVATE-BODY"
    end
  end

  test "show serializes every item" do
    bulk_create_entries(@feed, 30)

    get :show, params: {id: hex_encode(@feed.feed_url)}, format: :json

    assert_response :success
    assert_equal @feed.entries.count, parse_json["items"].size
  end

  test "show returns the newest items first" do
    older = create_entry(@feed)
    older.update!(published: 2.days.ago)
    newer = create_entry(@feed)
    newer.update!(published: 1.minute.ago)

    get :show, params: {id: hex_encode(@feed.feed_url)}, format: :json

    assert_response :success
    assert_equal newer.id, parse_json["items"].first["id"]
  end

  test "refreshes a feed whose standalone flag is older than the TTL" do
    feed = feeds(:daring_fireball)
    feed.update!(standalone_request_at: (StandaloneRetention::TTL + 1.day).ago)

    status_mock = Minitest::Mock.new.expect(:perform, nil, [feed.id])
    update_mock = Minitest::Mock.new.expect(:perform, nil, [feed.id])

    FeedStatus.stub(:new, status_mock) do
      FeedUpdate.stub(:new, update_mock) do
        get :show, params: {id: hex_encode(feed.feed_url)}, format: :json
      end
    end

    assert_response :success
    status_mock.verify
    update_mock.verify
  end

  test "does not refresh a feed whose standalone flag is inside the TTL" do
    feed = feeds(:daring_fireball)
    feed.update!(standalone_request_at: 1.day.ago)

    called = false
    FeedStatus.stub(:new, ->(*) { called = true }) do
      get :show, params: {id: hex_encode(feed.feed_url)}, format: :json
    end

    assert_response :success
    refute called, "expected the refresh to be skipped for a feed requested inside the TTL"
  end

  test "still refreshes a feed whose standalone flag is blank" do
    feed = feeds(:daring_fireball)
    feed.update_column(:standalone_request_at, nil)

    status_mock = Minitest::Mock.new.expect(:perform, nil, [feed.id])
    update_mock = Minitest::Mock.new.expect(:perform, nil, [feed.id])

    FeedStatus.stub(:new, status_mock) do
      FeedUpdate.stub(:new, update_mock) do
        get :show, params: {id: hex_encode(feed.feed_url)}, format: :json
      end
    end

    assert_response :success
    status_mock.verify
    update_mock.verify
  end

  test "every item carries date_modified from the entry's updated_at" do
    entry = create_entry(@feed)
    entry.update_column(:updated_at, Time.utc(2026, 9, 4, 17, 16, 46, 453373))

    get :show, params: {id: hex_encode(@feed.feed_url)}, format: :json

    assert_response :success
    item = parse_json["items"].find { |i| i["id"] == entry.id }
    assert_equal "2026-09-04T17:16:46.453373Z", item["date_modified"]
  end

  test "updated_since returns only entries whose row changed after it" do
    entries = bulk_create_entries(@feed, 3)
    stale = entries.first
    stale.update_column(:updated_at, 2.days.ago)

    get :show, params: {id: hex_encode(@feed.feed_url), updated_since: 1.day.ago.iso8601(6)}, format: :json

    assert_response :success
    ids = parse_json["items"].map { |item| item["id"] }
    assert_equal (entries.map(&:id) - [stale.id]).sort, ids.sort
  end

  test "an empty delta is a success carrying the feed's fields and no items" do
    bulk_create_entries(@feed, 3)

    get :show, params: {id: hex_encode(@feed.feed_url), updated_since: 1.minute.from_now.iso8601(6)}, format: :json

    assert_response :success
    assert_equal @feed.id, parse_json["id"]
    assert_equal [], parse_json["items"]
  end

  test "an invalid updated_since is a 400" do
    get :show, params: {id: hex_encode(@feed.feed_url), updated_since: "yesterday"}, format: :json

    assert_response :bad_request
    assert_equal "Invalid ISO 8601 timestamp", parse_json["errors"].first["updated_since"]
  end

  test "a non-string updated_since is a 400, not a 500" do
    get :show, params: {id: hex_encode(@feed.feed_url), updated_since: ["2026-09-04T00:00:00Z"]}, format: :json

    assert_response :bad_request
    assert_equal "Invalid ISO 8601 timestamp", parse_json["errors"].first["updated_since"]
  end

  test "ids returns only those entries" do
    entries = bulk_create_entries(@feed, 3)
    wanted = entries.first(2)

    get :show, params: {id: hex_encode(@feed.feed_url), ids: wanted.map(&:id).join(",")}, format: :json

    assert_response :success
    assert_equal wanted.map(&:id).sort, parse_json["items"].map { |item| item["id"] }.sort
  end

  test "ids from another feed yield nothing" do
    foreign = create_entry(feeds(:kottke))

    get :show, params: {id: hex_encode(@feed.feed_url), ids: foreign.id.to_s}, format: :json

    assert_response :success
    assert_equal [], parse_json["items"]
  end

  test "ids wins over updated_since" do
    entry = create_entry(@feed)

    get :show, params: {id: hex_encode(@feed.feed_url), ids: entry.id.to_s, updated_since: 1.minute.from_now.iso8601(6)}, format: :json

    assert_response :success
    assert_equal [entry.id], parse_json["items"].map { |item| item["id"] }
  end

  test "more than 100 ids is a 400" do
    get :show, params: {id: hex_encode(@feed.feed_url), ids: (1..101).to_a.join(",")}, format: :json

    assert_response :bad_request
    assert_match(/100 ids/, parse_json["errors"].first["ids"])
  end

  test "an empty ids falls through to the other shapes" do
    bulk_create_entries(@feed, 2)

    get :show, params: {id: hex_encode(@feed.feed_url), ids: ""}, format: :json

    assert_response :success
    assert_equal 2, parse_json["items"].size
  end

  test "a non-string ids is a 400" do
    get :show, params: {id: hex_encode(@feed.feed_url), ids: ["1"]}, format: :json

    assert_response :bad_request
  end

  test "a full response is capped at max_items, newest first" do
    entries = bulk_create_entries(@feed, 3)

    Api::Podcasts::V1::FeedsController.stub(:max_items, 2) do
      get :show, params: {id: hex_encode(@feed.feed_url)}, format: :json
    end

    assert_response :success
    assert_equal entries.last(2).map(&:id).reverse, parse_json["items"].map { |item| item["id"] }
  end

  test "a delta is capped at max_items too" do
    bulk_create_entries(@feed, 3)

    Api::Podcasts::V1::FeedsController.stub(:max_items, 2) do
      get :show, params: {id: hex_encode(@feed.feed_url), updated_since: 1.day.ago.iso8601(6)}, format: :json
    end

    assert_response :success
    assert_equal 2, parse_json["items"].size
  end

  private

  def hex_encode(string)
    string.unpack1("H*")
  end
end
