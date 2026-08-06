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
    30.times { create_entry(@feed) }

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

  private

  def hex_encode(string)
    string.unpack1("H*")
  end
end
