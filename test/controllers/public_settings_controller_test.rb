require "test_helper"

class PublicSettingsControllerTest < ActionController::TestCase
  test "should unsubscribe from emails" do
    @user = users(:ben)
    refute @user.reload.setting_on?(:marketing_unsubscribe)

    unsubscribe = Rails.application.message_verifier(:unsubscribe).generate(@user.id)
    get :email_unsubscribe, params: {id: unsubscribe}
    assert_response :success
    assert @user.reload.setting_on?(:marketing_unsubscribe)
  end
end
