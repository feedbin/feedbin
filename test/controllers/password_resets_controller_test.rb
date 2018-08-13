require "test_helper"

class PasswordResetsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "gets new" do
    get :new
    assert_response :success
  end

  test "should create password reset" do
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        post :create, params: {email: @user.email}
      end
      assert_not_equal @user.password_reset_token, @user.reload.password_reset_token
    end
  end

  test "should get edit" do
    token = @user.generate_token(:password_reset_token, nil, true)
    @user.save
    get :edit, params: {id: token}
    assert_response :success
  end

  test "should update password" do
    token = @user.generate_token(:password_reset_token, nil, true)
    @user.password_reset_sent_at = Time.now
    @user.save
    post :update, params: {id: token, user: {password: "new password"}}
    assert_redirected_to login_url
  end

  test "shouldn't update password with expired token" do
    token = @user.generate_token(:password_reset_token, nil, true)
    @user.password_reset_sent_at = 3.hours.ago
    @user.save
    post :update, params: {id: token, user: {password: "new password"}}
    assert_redirected_to new_password_reset_path
    assert flash[:alert].present?
  end
end
