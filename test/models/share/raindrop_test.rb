require "test_helper"

class Share::RaindropTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(content: "<p>x</p>", title: "Title", url: "/p/1", public_id: SecureRandom.hex)
    @klass = @user.supported_sharing_services.create!(service_id: "raindrop")
    @klass.update!(oauth2_token: {access_token: "tok", expires_at: (Time.now + 3600).to_i}.to_json)
  end

  test "consumer wires up an OAuth2::Client with raindrop endpoints" do
    consumer = Share::Raindrop.new.consumer
    assert_kind_of OAuth2::Client, consumer
    assert_equal "https://api.raindrop.io", consumer.site
    assert_equal "/v1/oauth/access_token", consumer.options[:token_url]
    assert_equal "/v1/oauth/authorize", consumer.options[:authorize_url]
  end

  test "redirect_uri builds the oauth2_response URL for raindrop" do
    s = Share::Raindrop.new
    assert_match %r{/supported_sharing_services/raindrop/oauth2_response}, s.redirect_uri
  end

  test "authorize_redirect produces an authorize URL with the redirect_uri query" do
    s = Share::Raindrop.new
    url = s.authorize_redirect({})
    assert_match %r{/v1/oauth/authorize}, url
    assert_match %r{redirect_uri=}, url
  end

  test "request_access exchanges a code for an oauth2_token hash" do
    fake_token = OpenStruct.new(to_hash: {access_token: "new"})
    captured = nil
    fake_auth_code = Object.new
    fake_auth_code.define_singleton_method(:get_token) { |code, opts| captured = [code, opts]; fake_token }
    fake_consumer = Object.new
    fake_consumer.define_singleton_method(:auth_code) { fake_auth_code }
    s = Share::Raindrop.new
    s.stub :consumer, fake_consumer do
      result = s.request_access(code: "abc")
      assert_match %r{access_token}, result[:oauth2_token]
    end
    assert_equal "abc", captured.first
    assert_equal "authorization_code", captured.last[:grant_type]
  end

  test "share delegates to authenticated_share" do
    share = Share::Raindrop.new(@klass)
    share.stub :authenticated_share, ->(*) { :ok } do
      assert_equal :ok, share.share({})
    end
  end

  test "add posts to the raindrop bookmarks endpoint and returns the response code" do
    fake_response = OpenStruct.new(status: OpenStruct.new(code: 200))
    HTTP.stub :headers, ->(*) {
      Class.new {
        define_method(:post) { |*args| fake_response }
      }.new
    } do
      share = Share::Raindrop.new(@klass)
      assert_equal 200, share.add(entry_id: @entry.id)
    end
  end

  test "add refreshes an expired token and updates the klass" do
    @klass.update!(oauth2_token: {access_token: "old", expires_at: (Time.now - 60).to_i}.to_json)
    fake_response = OpenStruct.new(status: OpenStruct.new(code: 200))
    refreshed = OpenStruct.new(
      to_hash: {access_token: "new"},
      headers: {},
      client: OpenStruct.new(connection: OpenStruct.new)
    )
    refreshed.client.connection.define_singleton_method(:build_url) { |path| "https://api.raindrop.io#{path}" }
    fake_token = Object.new
    fake_token.define_singleton_method(:expired?) { true }
    fake_token.define_singleton_method(:refresh!) { refreshed }
    OAuth2::AccessToken.stub :from_hash, ->(*) { fake_token } do
      HTTP.stub :headers, ->(*) {
        Class.new {
          define_method(:post) { |*| fake_response }
        }.new
      } do
        share = Share::Raindrop.new(@klass)
        share.add(entry_id: @entry.id)
        assert_equal({access_token: "new"}.to_json, @klass.reload.oauth2_token)
      end
    end
  end
end
