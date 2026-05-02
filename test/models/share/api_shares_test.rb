require "test_helper"

class Share::ApiSharesTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(
      content: "<p>hi</p>",
      title: "Hi",
      url: "https://example.com/p/1",
      public_id: SecureRandom.hex
    )
  end

  # ---- Share::Pinboard --------------------------------------------------------

  test "Pinboard#request_token returns a token wrapper on success" do
    stub_request(:get, %r{api\.pinboard\.in/v1/user/api_token}).to_return(status: 200, body: "{}")
    result = Share::Pinboard.new.request_token("user", "tok")
    assert_equal "tok", result.token
    assert_equal "n/a", result.secret
  end

  test "Pinboard#request_token raises OAuth::Unauthorized when API returns non-200" do
    stub_request(:get, %r{api\.pinboard\.in/v1/user/api_token}).to_return(status: 401, body: "")
    assert_raises(OAuth::Unauthorized) do
      Share::Pinboard.new.request_token("user", "bad")
    end
  end

  test "Pinboard#add returns 200 when API result_code is done" do
    klass = @user.supported_sharing_services.create!(service_id: "pinboard", access_token: "tok")
    stub_request(:get, %r{api\.pinboard\.in/v1/posts/add}).to_return(status: 200, body: '{"result_code":"done"}')
    assert_equal 200, Share::Pinboard.new(klass).add(url: "https://x", description: "x")
  end

  test "Pinboard#add returns 500 when result_code is not done" do
    klass = @user.supported_sharing_services.create!(service_id: "pinboard", access_token: "tok")
    stub_request(:get, %r{api\.pinboard\.in/v1/posts/add}).to_return(status: 200, body: '{"result_code":"item already exists"}')
    assert_equal 500, Share::Pinboard.new(klass).add(url: "https://x")
  end

  test "Pinboard#add returns the response code when API returns non-200" do
    klass = @user.supported_sharing_services.create!(service_id: "pinboard", access_token: "tok")
    stub_request(:get, %r{api\.pinboard\.in/v1/posts/add}).to_return(status: 503, body: "")
    assert_equal 503, Share::Pinboard.new(klass).add(url: "https://x")
  end

  test "Pinboard#share delegates to authenticated_share" do
    klass = @user.supported_sharing_services.create!(service_id: "pinboard", access_token: "tok")
    share = Share::Pinboard.new(klass)
    share.stub :authenticated_share, ->(_k, params) { {ok: params[:url]} } do
      assert_equal({ok: "x"}, share.share(url: "x"))
    end
  end

  # ---- Share::MicroBlog -------------------------------------------------------

  test "MicroBlog#request_token returns a token wrapper on success" do
    stub_request(:post, %r{micro\.blog/account/verify}).to_return(status: 200, body: '{"token":"tok"}', headers: {"Content-Type" => "application/json"})
    result = Share::MicroBlog.new.request_token("user", "tok")
    assert_equal "tok", result.token
  end

  test "MicroBlog#request_token raises OAuth::Unauthorized on bad credentials" do
    stub_request(:post, %r{micro\.blog/account/verify}).to_return(status: 401, body: "{}", headers: {"Content-Type" => "application/json"})
    assert_raises(OAuth::Unauthorized) do
      Share::MicroBlog.new.request_token("user", "bad")
    end
  end

  test "MicroBlog#add returns 200 when API returns 202" do
    klass = @user.supported_sharing_services.create!(service_id: "micro_blog", access_token: "tok")
    stub_request(:post, "https://micro.blog/micropub")
      .to_return(status: 202, body: "")
    assert_equal 200, Share::MicroBlog.new(klass).add("content" => "hi", "name" => "title")
  end

  test "MicroBlog#add returns 500 when API does not accept" do
    klass = @user.supported_sharing_services.create!(service_id: "micro_blog", access_token: "tok")
    stub_request(:post, "https://micro.blog/micropub")
      .to_return(status: 500, body: "")
    assert_equal 500, Share::MicroBlog.new(klass).add("content" => "hi")
  end

  test "MicroBlog#add returns 500 when the request times out" do
    klass = @user.supported_sharing_services.create!(service_id: "micro_blog", access_token: "tok")
    stub_request(:post, "https://micro.blog/micropub").to_timeout
    assert_equal 500, Share::MicroBlog.new(klass).add("content" => "hi")
  end

  test "MicroBlog#share delegates to authenticated_share" do
    klass = @user.supported_sharing_services.create!(service_id: "micro_blog", access_token: "tok")
    share = Share::MicroBlog.new(klass)
    share.stub :authenticated_share, ->(_k, params) { {ok: params[:content]} } do
      assert_equal({ok: "x"}, share.share(content: "x"))
    end
  end

  # ---- Share::Readability -----------------------------------------------------

  test "Readability#consumer wires up the OAuth::Consumer with the access_token_path" do
    consumer = Share::Readability.new.consumer
    assert_kind_of OAuth::Consumer, consumer
    assert_equal "https://www.readability.com", consumer.options[:site]
    assert_equal "/api/rest/v1/oauth/access_token/", consumer.options[:access_token_path]
  end

  test "Readability#request_token forwards xAuth params to the consumer" do
    captured = nil
    fake_consumer = Object.new
    fake_consumer.define_singleton_method(:get_access_token) { |*args| captured = args; :access }
    s = Share::Readability.new
    s.stub :consumer, fake_consumer do
      assert_equal :access, s.request_token("user", "pw")
    end
    assert_equal "user", captured.last[:x_auth_username]
    assert_equal "client_auth", captured.last[:x_auth_mode]
  end

  test "Readability#add normalizes 202 and 409 to 200" do
    klass = @user.supported_sharing_services.create!(service_id: "readability", access_token: "tok", access_secret: "sec")
    fake_response = OpenStruct.new(code: "202")
    fake_client = Object.new
    fake_client.define_singleton_method(:post) { |*| fake_response }
    OAuth::AccessToken.stub :new, fake_client do
      share = Share::Readability.new(klass)
      assert_equal 200, share.add("entry_url" => "https://x")
    end
    fake_response_409 = OpenStruct.new(code: "409")
    fake_client_409 = Object.new
    fake_client_409.define_singleton_method(:post) { |*| fake_response_409 }
    OAuth::AccessToken.stub :new, fake_client_409 do
      share = Share::Readability.new(klass)
      assert_equal 200, share.add("entry_url" => "https://x")
    end
  end

  test "Readability#add returns the response code for non-2xx responses" do
    klass = @user.supported_sharing_services.create!(service_id: "readability", access_token: "tok", access_secret: "sec")
    fake_response = OpenStruct.new(code: "500")
    fake_client = Object.new
    fake_client.define_singleton_method(:post) { |*| fake_response }
    OAuth::AccessToken.stub :new, fake_client do
      share = Share::Readability.new(klass)
      assert_equal 500, share.add("entry_url" => "https://x")
    end
  end

  test "Readability#share delegates to authenticated_share" do
    klass = @user.supported_sharing_services.create!(service_id: "readability", access_token: "tok", access_secret: "sec")
    OAuth::AccessToken.stub :new, Object.new do
      share = Share::Readability.new(klass)
      share.stub :authenticated_share, ->(*) { :ok } do
        assert_equal :ok, share.share({})
      end
    end
  end
end
