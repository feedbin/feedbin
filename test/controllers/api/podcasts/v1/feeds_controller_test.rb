require "test_helper"

class Api::Podcasts::V1::FeedsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @feed.update!(standalone_request_at: Time.now)
  end

  # The endpoint is anonymous, so an unbounded item list is a small request
  # that makes Feedbin render a podcast's whole history.
  test "show limits how many items it serializes" do
    30.times { create_entry(@feed) }

    statements = capture_sql do
      get :show, params: {id: @feed.feed_url.unpack1("H*")}, format: :json
    end

    assert_response :success
    assert_operator parse_json["items"].size, :<=, 25
    entry_selects = statements.select { _1.match?(/FROM "entries"/i) }
    assert entry_selects.any? { _1.match?(/LIMIT/i) }, "the item query carries no LIMIT: #{entry_selects.inspect}"
  end

  test "show returns the newest items first" do
    older = create_entry(@feed)
    older.update!(published: 2.days.ago)
    newer = create_entry(@feed)
    newer.update!(published: 1.minute.ago)

    get :show, params: {id: @feed.feed_url.unpack1("H*")}, format: :json

    assert_response :success
    assert_equal newer.id, parse_json["items"].first["id"]
  end
end
