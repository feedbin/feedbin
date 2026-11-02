require "test_helper"
require Rails.root.join("db/migrate/20261102130000_split_full_scope")

class ApiV3ScopesTest < ActionDispatch::IntegrationTest
  REDIRECT_URI = "myreader://oauth/callback"

  setup do
    host! "api.example.com"
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @third_party = users(:ann).oauth_applications.create!(name: "My Reader", redirect_uri: REDIRECT_URI)
    @first_party = users(:ann).oauth_applications.create!(name: "Feedbin", redirect_uri: REDIRECT_URI, scopes: "read write account")
    @reader = @third_party.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write")
    @feedbin = @first_party.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "third-party token cannot register a device" do
    post "/v3/devices", params: device_body, headers: bearer(@reader), as: :json

    assert_insufficient_scope
  end

  test "first-party token registers a device" do
    post "/v3/devices", params: device_body, headers: bearer(@feedbin), as: :json

    assert_response :created
  end

  test "third-party token cannot delete a device" do
    device = @user.devices.create!(token: "abc123", device_type: :notifier)

    delete "/v3/devices/#{device.id}", headers: bearer(@reader)

    assert_insufficient_scope
    assert Device.exists?(device.id)
  end

  test "third-party token cannot delete the account" do
    delete "/v3/account", headers: bearer(@reader)

    assert_insufficient_scope
    refute @reader.reload.revoked?
  end

  test "first-party token deletes the account" do
    delete "/v3/account", headers: bearer(@feedbin)

    assert_response :no_content
  end

  test "third-party token cannot record a purchase" do
    post "/v3/account/purchases", params: {receipt_data: "abc"}, headers: bearer(@reader), as: :json

    assert_insufficient_scope
  end

  test "first-party token reaches purchases" do
    AppStoreReceipt.stub(:verify, {"status" => 21002}) do
      post "/v3/account/purchases", params: {receipt_data: "abc"}, headers: bearer(@feedbin), as: :json
    end

    assert_response :unprocessable_content
  end

  test "third-party token reads and updates the account" do
    get "/v3/account", headers: bearer(@reader)
    assert_response :success

    patch "/v3/account", params: {settings: {}}, headers: bearer(@reader), as: :json
    assert_response :success
  end

  test "third-party token cannot list tokens" do
    get "/v3/tokens", headers: bearer(@reader)

    assert_insufficient_scope
  end

  test "first-party token lists tokens" do
    get "/v3/tokens", headers: bearer(@feedbin)

    assert_response :success
  end

  test "any token revokes itself" do
    delete "/v3/tokens/#{@reader.id}", headers: bearer(@reader)

    assert_response :no_content
    assert @reader.reload.revoked?
  end

  test "third-party token cannot revoke another token" do
    delete "/v3/tokens/#{@feedbin.id}", headers: bearer(@reader)

    assert_insufficient_scope
    refute @feedbin.reload.revoked?
  end

  test "first-party token revokes another token" do
    delete "/v3/tokens/#{@reader.id}", headers: bearer(@feedbin)

    assert_response :no_content
  end

  test "third party asking for account gets read write" do
    assert_equal "read write", authorize(@third_party, scope: "account")
  end

  test "third party asking for read gets read write" do
    assert_equal "read write", authorize(@third_party, scope: "read")
  end

  test "third party asking for nothing gets read write" do
    assert_equal "read write", authorize(@third_party)
  end

  test "first party gets account without asking" do
    assert_equal "read write account", authorize(@first_party)
  end

  test "migrated full tokens keep reading and only Feedbin's development app keeps account" do
    development = Api::V3::DevelopmentApplication.ensure!(owner: users(:ann))
    development.update_column(:scopes, "")
    @third_party.update_column(:scopes, "full")
    old = @third_party.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
    dev = development.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")

    ActiveRecord::Migration.suppress_messages { SplitFullScope.new.up }

    assert_equal "read write", old.reload.scopes.to_s
    assert_equal "read write account", dev.reload.scopes.to_s
    assert_equal "read write account", development.reload.scopes.to_s
    assert_equal "", @third_party.reload.scopes.to_s
    assert_equal "read write", authorize(@third_party)
    host! "api.example.com"
    get "/v3/subscriptions", headers: bearer(old)
    assert_response :success
  end

  test "the migration marks the first-party apps named in the environment" do
    production = users(:ann).oauth_applications.create!(name: "Feedbin", redirect_uri: REDIRECT_URI)
    token = production.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
    original = ENV["API_V3_FIRST_PARTY_UIDS"]
    ENV["API_V3_FIRST_PARTY_UIDS"] = "#{production.uid}, unknown-uid"

    ActiveRecord::Migration.suppress_messages { SplitFullScope.new.up }

    assert_equal "read write account", production.reload.scopes.to_s
    assert_equal "read write account", token.reload.scopes.to_s
  ensure
    ENV["API_V3_FIRST_PARTY_UIDS"] = original
  end

  # A token minted by a process still running the old code after the
  # migration has run.
  test "a leftover full token has the scopes of its app" do
    leftover_feedbin = @first_party.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
    leftover_reader = @third_party.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")

    get "/v3/tokens", headers: bearer(leftover_feedbin)
    assert_response :success

    get "/v3/tokens", headers: bearer(leftover_reader)
    assert_insufficient_scope
  end

  test "revoking another token is a scope error whether or not the id exists" do
    delete "/v3/tokens/0", headers: bearer(@reader)

    assert_insufficient_scope
  end

  private

  def bearer(token)
    {"Authorization" => "Bearer #{token.plaintext_token}"}
  end

  def device_body
    {push_token: "abc123", platform: "ios", app_bundle_id: "com.feedbin.app"}
  end

  def assert_insufficient_scope
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["code"]
    assert_includes response.headers["WWW-Authenticate"], %(error="insufficient_scope", scope="account")
  end

  # Runs the authorization-code flow and returns the issued token's scopes.
  def authorize(application, scope: nil)
    verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    params = {client_id: application.uid, redirect_uri: REDIRECT_URI, response_type: "code", state: "abc", code_challenge: challenge, code_challenge_method: "S256"}
    params[:scope] = scope if scope

    host! "www.example.com"
    sign_in_as @user
    get oauth_authorization_path(params)
    assert_response :success
    post oauth_authorization_path, params: params
    assert_response :redirect
    code = Rack::Utils.parse_query(URI(response.location).query)["code"]
    post oauth_token_path, params: {grant_type: "authorization_code", client_id: application.uid, redirect_uri: REDIRECT_URI, code: code, code_verifier: verifier}
    assert_response :success
    JSON.parse(response.body)["scope"]
  end
end
