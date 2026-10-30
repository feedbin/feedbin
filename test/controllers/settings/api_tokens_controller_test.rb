require "test_helper"

class Settings::ApiTokensControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.setting_on!(:api_v3)
    @application = @user.oauth_applications.create!(name: "My Reader", redirect_uri: "")
  end

  test "creates a token and shows it once" do
    login_as @user

    assert_difference -> { @user.oauth_access_tokens.count }, 1 do
      post :create, params: {api_application_id: @application, token: {device_name: "curl on my Mac"}}
    end

    token = @user.oauth_access_tokens.last
    assert_redirected_to settings_api_application_path(@application)
    assert_equal "curl on my Mac", token.device_name
    assert_nil token.expires_in
    assert flash[:plaintext_token].start_with?("fbn_v3_")
    assert_equal token, Doorkeeper::AccessToken.by_token(flash[:plaintext_token])
  end

  test "does not create a token for another user's application" do
    application = users(:ann).oauth_applications.create!(name: "Not Yours", redirect_uri: "")
    login_as @user

    assert_raises(ActiveRecord::RecordNotFound) do
      post :create, params: {api_application_id: application}
    end
  end

  test "revokes a token" do
    token = @application.access_tokens.create!(resource_owner_id: @user.id, scopes: "")
    login_as @user

    delete :destroy, params: {api_application_id: @application, id: token}

    assert token.reload.revoked?
  end

  test "does not revoke another user's token" do
    token = @application.access_tokens.create!(resource_owner_id: users(:ann).id, scopes: "")
    login_as @user

    assert_raises(ActiveRecord::RecordNotFound) do
      delete :destroy, params: {api_application_id: @application, id: token}
    end
  end

  test "is hidden without the feature flag" do
    @user.setting_off!(:api_v3)
    login_as @user

    post :create, params: {api_application_id: @application}

    assert_response :not_found
  end
end
