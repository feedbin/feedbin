require "test_helper"

class FirebaseMessagingTest < ActiveSupport::TestCase
  TOKEN_URI = "https://oauth2.googleapis.com/token"
  SEND_URL = "https://fcm.googleapis.com/v1/projects/airshow-test/messages:send"

  setup do
    @key = OpenSSL::PKey::RSA.new(2048)
    @credentials = Tempfile.new(["firebase", ".json"])
    @credentials.write({
      project_id: "airshow-test",
      client_email: "push@airshow-test.iam.gserviceaccount.com",
      private_key: @key.to_pem,
      token_uri: TOKEN_URI
    }.to_json)
    @credentials.flush
    @messaging = FirebaseMessaging.new(@credentials.path)
    @token_request = stub_request(:post, TOKEN_URI)
      .to_return(status: 200, body: {access_token: "access-1", expires_in: 3599}.to_json, headers: {"Content-Type" => "application/json"})
  end

  teardown do
    @credentials.close!
  end

  test "sends the message with an access token from a signed service-account assertion" do
    send = stub_request(:post, SEND_URL)
      .with(headers: {"Authorization" => "Bearer access-1"}, body: {message: {token: "device", data: {a: "1"}}}.to_json)
      .to_return(status: 200, body: {name: "projects/airshow-test/messages/1"}.to_json)

    response = @messaging.deliver(token: "device", data: {a: "1"})

    assert response.success?
    assert_requested send
    assert_requested(:post, TOKEN_URI) do |request|
      form = URI.decode_www_form(request.body).to_h
      claims, = JWT.decode(form["assertion"], @key.public_key, true, algorithm: "RS256")
      form["grant_type"] == FirebaseMessaging::GRANT_TYPE &&
        claims["iss"] == "push@airshow-test.iam.gserviceaccount.com" &&
        claims["scope"] == FirebaseMessaging::SCOPE &&
        claims["aud"] == TOKEN_URI
    end
  end

  test "reuses the access token until it is about to expire" do
    stub_request(:post, SEND_URL).to_return(status: 200, body: "{}")

    @messaging.deliver(token: "device")
    @messaging.deliver(token: "device")
    assert_requested @token_request, times: 1

    travel 59.minutes do
      @messaging.deliver(token: "device")
    end
    assert_requested @token_request, times: 2
  end

  test "reports an unregistered token" do
    stub_request(:post, SEND_URL).to_return(
      status: 404,
      body: {error: {code: 404, status: "NOT_FOUND", details: [{"@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode" => "UNREGISTERED"}]}}.to_json
    )

    response = @messaging.deliver(token: "gone")

    refute response.success?
    assert response.unregistered?
    assert_equal "UNREGISTERED", response.error_code
  end

  test "a failure that isn't about the token leaves it registered" do
    stub_request(:post, SEND_URL).to_return(status: 503, body: "Service Unavailable")

    response = @messaging.deliver(token: "device")

    refute response.success?
    refute response.unregistered?
    assert_nil response.error_code
  end

  test "raises when the access token can't be fetched" do
    stub_request(:post, TOKEN_URI).to_return(status: 401, body: "{}")

    assert_raises(FirebaseMessaging::Error) { @messaging.deliver(token: "device") }
  end
end
