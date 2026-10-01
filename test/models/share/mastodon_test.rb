require "test_helper"

class Share::MastodonTest < ActiveSupport::TestCase
  test "app registration does not connect to a private server" do
    server = TCPServer.new("127.0.0.1", 0)
    url = "127.0.0.1:#{server.addr[1]}"

    assert_raises Share::Service::AuthError do
      Share::Mastodon.new.authorize_redirect({mastodon_url: url}, "state")
    end

    assert_raises(IO::WaitReadable, "registration reached the private socket") { server.accept_nonblock }
  ensure
    server&.close
  end

  test "OAuth token transport does not connect to a private server" do
    server = TCPServer.new("127.0.0.1", 0)
    url = "https://127.0.0.1:#{server.addr[1]}"
    OauthServer.create!(host: "127.0.0.1", data: {"client_id" => "id", "client_secret" => "secret"})
    service = Share::Mastodon.new
    client = service.client("id", "secret", "127.0.0.1")
    client.site = url

    service.stub(:client, client) do
      assert_raises Share::Service::AuthError do
        service.request_access(code: "code", mastodon_host: "127.0.0.1")
      end
    end

    assert_raises(IO::WaitReadable, "OAuth reached the private socket") { server.accept_nonblock }
  ensure
    server&.close
  end

  test "token requests reject redirects without sending credentials to the target" do
    OauthServer.create!(host: "social.example", data: {"client_id" => "id", "client_secret" => "secret"})
    stub_request(:post, "https://social.example/oauth/token")
      .to_return(status: 307, headers: {location: "https://redirect.example/oauth/token"})
    stub_request(:post, "https://redirect.example/oauth/token")
      .to_return(body: {access_token: "token"}.to_json, headers: {content_type: "application/json"})

    assert_raises Share::Service::AuthError do
      Share::Mastodon.new.request_access(code: "code", mastodon_host: "social.example")
    end

    assert_not_requested :post, "https://redirect.example/oauth/token"
  end

  test "token requests reject malformed or missing access tokens" do
    OauthServer.create!(host: "social.example", data: {"client_id" => "id", "client_secret" => "secret"})

    ["not json", "{}", "[]", '{"access_token":null}', '{"access_token":""}', '{"access_token":123}'].each do |body|
      stub_request(:post, "https://social.example/oauth/token")
        .to_return(body: body, headers: {content_type: "application/json"})

      assert_raises(Share::Service::AuthError, "accepted #{body}") do
        Share::Mastodon.new.request_access(code: "code", mastodon_host: "social.example")
      end
    end
  end

  test "token request reports a private server as an authorization error" do
    OauthServer.create!(host: "127.0.0.1", data: {"client_id" => "id", "client_secret" => "secret"})

    assert_raises Share::Service::AuthError do
      Share::Mastodon.new.request_access(code: "code", mastodon_host: "127.0.0.1")
    end
  end

  test "status posting does not connect to a private server" do
    server = TCPServer.new("127.0.0.1", 0)
    client = Struct.new(:headers, :client).new({}, Struct.new(:connection).new(
      Struct.new(:url) { def build_url(*) = url }.new("http://127.0.0.1:#{server.addr[1]}/api/v1/statuses")
    ))
    service = Share::Mastodon.new
    service.instance_variable_set(:@client, client)

    assert_equal :unreachable, service.add(status: "hello", idempotency_key: "key")

    assert_raises(IO::WaitReadable, "status reached the private socket") { server.accept_nonblock }
  ensure
    server&.close
  end
end
