require "test_helper"

class PublicSettingsControllerTest < ActionController::TestCase
  test "should unsubscribe from emails" do
    @user = users(:ben)
    assert @user.reload.subscribed_to_emails?

    unsubscribe = Rails.application.message_verifier(:unsubscribe).generate(@user.id)
    get :email_unsubscribe, params: {id: unsubscribe}
    assert_response :success
    assert !@user.reload.subscribed_to_emails?
  end
end
