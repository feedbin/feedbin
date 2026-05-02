require "test_helper"

class Share::InstapaperTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @klass = @user.supported_sharing_services.create!(service_id: "instapaper")
  end

  test "consumer wires up the OAuth::Consumer with the access_token_path" do
    consumer = Share::Instapaper.new.consumer
    assert_kind_of OAuth::Consumer, consumer
    assert_equal "https://www.instapaper.com", consumer.options[:site]
    assert_equal "/api/1/oauth/access_token", consumer.options[:access_token_path]
  end

  test "request_token forwards xAuth params to consumer.get_access_token" do
    captured = nil
    fake_consumer = Object.new
    fake_consumer.define_singleton_method(:get_access_token) { |*args| captured = args; :access }
    s = Share::Instapaper.new
    s.stub :consumer, fake_consumer do
      assert_equal :access, s.request_token("user", "pw")
    end
    assert_equal "user", captured.last[:x_auth_username]
  end

  test "initializer skips wiring up the access token when credentials are missing" do
    @klass.update!(access_token: nil, access_secret: nil)
    share = Share::Instapaper.new(@klass)
    assert_nil share.instance_variable_get(:@client)
  end

  test "add normalizes 201 to 200" do
    @klass.update!(access_token: "tok", access_secret: "sec")
    fake_response = OpenStruct.new(code: "201")
    fake_client = Object.new
    fake_client.define_singleton_method(:post) { |*| fake_response }
    OAuth::AccessToken.stub :new, fake_client do
      share = Share::Instapaper.new(@klass)
      assert_equal 200, share.add("entry_url" => "https://x")
    end
  end

  test "add returns the response code for non-201 responses" do
    @klass.update!(access_token: "tok", access_secret: "sec")
    fake_response = OpenStruct.new(code: "500")
    fake_client = Object.new
    fake_client.define_singleton_method(:post) { |*| fake_response }
    OAuth::AccessToken.stub :new, fake_client do
      share = Share::Instapaper.new(@klass)
      assert_equal 500, share.add("entry_url" => "https://x")
    end
  end

  test "share delegates to authenticated_share" do
    @klass.update!(access_token: "tok", access_secret: "sec")
    OAuth::AccessToken.stub :new, Object.new do
      share = Share::Instapaper.new(@klass)
      share.stub :authenticated_share, ->(*) { :ok } do
        assert_equal :ok, share.share({})
      end
    end
  end
end
