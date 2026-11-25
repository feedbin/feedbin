require "test_helper"

class ApiV3AccountTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "shows the account with plan, settings, newsletter address and page token" do
    @user.update!(settings: @user.settings.merge("hide_airshow" => "1", "podcast_sort_order" => "newest_first", "podcast_download_limit" => "25"))

    get "/v3/account", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[object id email created_at plan newsletter_address settings], body.keys
    assert_equal ["account", @user.id, @user.email, @user.created_at.utc.iso8601], body.values_at("object", "id", "email", "created_at")
    assert_equal({"id" => "monthly", "name" => "Monthly", "status" => "active", "expires_at" => nil}, body["plan"].except("billing"))
    assert_equal "web", body["plan"]["billing"]["source"]
    assert_equal @user.newsletter_address, body["newsletter_address"]
    assert_equal({"podcast_sort" => "published_desc", "podcast_download_limit" => 25, "hide_queue" => true, "hide_recently_read" => false, "hide_updated" => false, "hide_recently_played" => false}, body["settings"])
  end

  test "an expired account reports its plan as expired" do
    @user.update!(suspended: true)
    get "/v3/account", headers: bearer
    assert_response :success
    assert_equal "expired", JSON.parse(response.body)["plan"]["status"]
    get "/v3/subscriptions", headers: bearer
    assert_response :forbidden

    @user.update_columns(suspended: false, expires_at: 1.day.ago, plan_id: Plan.find_by!(stripe_id: "timed").id)
    get "/v3/account", headers: bearer
    assert_equal "expired", JSON.parse(response.body)["plan"]["status"]
  end

  test "a plan's id names the plan, not its Stripe price" do
    {"basic-yearly-3" => "yearly", "basic-monthly-2" => "monthly", "trial" => "trial", "app-subscription" => "app_subscription"}.each do |stripe_id, id|
      @user.update_columns(plan_id: Plan.find_by!(stripe_id: stripe_id).id)
      get "/v3/account", headers: bearer
      assert_equal id, JSON.parse(response.body)["plan"]["id"], stripe_id
    end
  end

  test "updates settings as a merge patch" do
    patch "/v3/account", params: {settings: {hide_recently_played: true, podcast_sort: "manual", podcast_download_limit: 5}}.to_json, headers: json

    assert_response :success
    settings = JSON.parse(response.body)["settings"]
    assert_equal [true, "manual", 5, false], settings.values_at("hide_recently_played", "podcast_sort", "podcast_download_limit", "hide_queue")
    assert @user.reload.setting_on?(:hide_recently_played)
    assert_equal "custom", @user.podcast_sort_order

    patch "/v3/account", params: {settings: {podcast_sort: "sideways"}}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/settings/podcast_sort", JSON.parse(response.body)["errors"].first["pointer"]

    patch "/v3/account", params: {email: "new@example.com"}.to_json, headers: json
    assert_response :success
    assert_equal @user.email, @user.reload.email
  end

  test "deletes the account in the background and revokes the token" do
    assert_difference -> { UserDeleter.jobs.size }, +1 do
      delete "/v3/account", headers: bearer
    end
    assert_response :no_content
    assert @token.reload.revoked?
    assert_equal [@user.id], UserDeleter.jobs.last["args"]

    get "/v3/account", headers: bearer
    assert_response :unauthorized
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
