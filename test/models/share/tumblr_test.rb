require "test_helper"

class Share::TumblrTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(
      content: "<p>hello</p>",
      title: "Hello",
      url: "/p/1",
      public_id: SecureRandom.hex
    )
    @klass = @user.supported_sharing_services.create!(service_id: "tumblr")
    @klass.update!(access_token: "tok", access_secret: "sec")
    @fake_client = Object.new
    @captured_post = nil
    OAuth::AccessToken.stub :new, ->(_, _, _) { @fake_client } do
      @share = Share::Tumblr.new(@klass)
    end
  end

  test "consumer constructs an OAuth::Consumer with Tumblr endpoints" do
    consumer = Share::Tumblr.new.consumer
    assert_equal "https://www.tumblr.com", consumer.options[:site]
    assert_equal "/oauth/request_token", consumer.options[:request_token_path]
    assert_equal "/oauth/authorize", consumer.options[:authorize_path]
    assert_equal "/oauth/access_token", consumer.options[:access_token_path]
    assert_equal :post, consumer.options[:http_method]
  end

  test "request_token forwards to consumer.get_request_token" do
    captured = nil
    fake_consumer = Object.new
    fake_consumer.define_singleton_method(:get_request_token) { |opts| captured = opts; :tok }
    s = Share::Tumblr.new
    s.stub :consumer, fake_consumer do
      assert_equal :tok, s.request_token
    end
    assert_match %r{/supported_sharing_services/tumblr/oauth_response}, captured[:oauth_callback]
  end

  test "request_access uses OAuth::RequestToken.from_hash + get_access_token" do
    fake_request_token = Object.new
    captured = nil
    fake_request_token.define_singleton_method(:get_access_token) { |opts| captured = opts; :access }
    s = Share::Tumblr.new
    OAuth::RequestToken.stub :from_hash, ->(_, _) { fake_request_token } do
      assert_equal :access, s.request_access("t", "s", "vrf")
    end
    assert_equal "vrf", captured[:oauth_verifier]
  end

  test "response_valid? requires oauth_verifier" do
    s = Share::Tumblr.new
    assert s.response_valid?({}, {oauth_verifier: "v"})
    refute s.response_valid?({}, {})
  end

  test "user_info GETs /user/info and parses JSON" do
    fake_response = OpenStruct.new(body: '{"response":{"user":{"blogs":[]}}}')
    @fake_client.define_singleton_method(:get) { |url| fake_response }
    info = @share.user_info
    assert_equal({"response" => {"user" => {"blogs" => []}}}, info)
  end

  test "add posts a link by default and returns 200 when Tumblr returns 201" do
    captured = nil
    fake_response = OpenStruct.new(code: "201")
    @fake_client.define_singleton_method(:post) { |url, opts| captured = [url, opts]; fake_response }
    code = @share.add(
      site: "blog.tumblr.com",
      "format" => "html",
      "state" => "published",
      "entry_url" => "http://example.com/x",
      "title" => "T",
      "description" => "D",
      "tags" => "a,b"
    )
    assert_equal 200, code
    assert_equal "https://api.tumblr.com/v2/blog/blog.tumblr.com/post", captured[0]
    assert_equal "link", captured[1][:type]
    assert_equal "http://example.com/x", captured[1][:url]
    assert_equal "a,b", captured[1][:tags]
    assert_equal "blog.tumblr.com", @klass.reload.default_option
  end

  test "add posts a quote when type is quote" do
    captured = nil
    fake_response = OpenStruct.new(code: "200")
    @fake_client.define_singleton_method(:post) { |url, opts| captured = [url, opts]; fake_response }
    code = @share.add(
      site: "blog.tumblr.com",
      type: "quote",
      "format" => "html",
      "state" => "published",
      "source" => "src",
      "description" => "quoted text"
    )
    assert_equal 200, code
    assert_equal "quote", captured[1][:type]
    assert_equal "src", captured[1][:source]
    assert_equal "quoted text", captured[1][:quote]
  end

  test "share delegates to authenticated_share" do
    @share.stub :authenticated_share, ->(klass, params) { {forwarded: params} } do
      assert_equal({forwarded: {ok: 1}}, @share.share(ok: 1))
    end
  end

  test "after_activate returns the hosts of the user's Tumblr blogs" do
    fake_response = OpenStruct.new(body: '{"response":{"user":{"blogs":[{"url":"https://a.tumblr.com"},{"url":"https://b.tumblr.com"}]}}}')
    @fake_client.define_singleton_method(:get) { |url| fake_response }
    assert_equal ["a.tumblr.com", "b.tumblr.com"], @share.after_activate
  end
end
