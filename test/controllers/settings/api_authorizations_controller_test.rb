require "test_helper"

class Settings::ApiAuthorizationsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = users(:ann).oauth_applications.create!(name: "Their Reader", redirect_uri: "theirreader://callback")
  end

  test "revokes every sign-in the user has with an app" do
    tokens = 2.times.map { @application.access_tokens.create!(resource_owner_id: @user.id, scopes: "") }
    login_as @user

    delete :destroy, params: {id: @application.id}

    assert_redirected_to settings_account_path
    assert tokens.all? { it.reload.revoked? }
  end

  test "leaves other people's sign-ins and the user's created tokens alone" do
    theirs = @application.access_tokens.create!(resource_owner_id: users(:ann).id, scopes: "")
    own_app = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
    created = own_app.access_tokens.create!(resource_owner_id: @user.id, device_name: "curl on my Mac", scopes: "")
    signed_in = own_app.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    delete :destroy, params: {id: own_app.id}

    assert signed_in.reload.revoked?
    refute created.reload.revoked?
    refute theirs.reload.revoked?
  end

  test "works with API v3 off, so access granted earlier can still be revoked" do
    token = @application.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    @user.setting_off!(:api_v3)
    login_as @user

    delete :destroy, params: {id: @application.id}

    assert token.reload.revoked?
  end
end
