require "test_helper"

class ApiV3TokensTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    @token = @application.access_tokens.create!(resource_owner_id: @user.id, device_name: "Unread on Ben’s iPhone", scopes: "full")
    @other = @application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "lists the user's tokens" do
    get "/v3/tokens", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert body["meta"]["as_of"].present?

    current, other = body["data"].partition { _1["current"] }.map(&:first)
    assert_equal({"object" => "token", "id" => @token.id, "device_name" => "Unread on Ben’s iPhone", "created_at" => @token.created_at.utc.iso8601, "last_used_at" => @token.reload.last_used_at.utc.iso8601, "current" => true}, current)
    assert_equal "My Reader", other["device_name"]
    assert_nil other["last_used_at"]
    refute body["data"].any? { _1.key?("token") }
  end

  test "leaves out revoked tokens and other users' tokens" do
    @other.revoke
    @application.access_tokens.create!(resource_owner_id: users(:ann).id, scopes: "full")

    get "/v3/tokens", headers: bearer

    assert_equal [@token.id], JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "revokes a token" do
    delete "/v3/tokens/#{@other.id}", headers: bearer

    assert_response :no_content
    assert @other.reload.revoked?
  end

  test "a token can revoke itself" do
    delete "/v3/tokens/#{@token.id}", headers: bearer
    assert_response :no_content

    get "/v3/tokens", headers: bearer
    assert_response :unauthorized
  end

  test "does not revoke another user's token" do
    theirs = @application.access_tokens.create!(resource_owner_id: users(:ann).id, scopes: "full")

    delete "/v3/tokens/#{theirs.id}", headers: bearer

    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["code"]
    refute theirs.reload.revoked?
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
