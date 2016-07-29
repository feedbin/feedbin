require 'test_helper'

class PasswordResetsControllerTest < ActionController::TestCase

  setup do
    @user = users(:ben)
  end

  test "gets new" do
    get :new
    assert_response :success
  end

  test "should create password reset" do
    Sidekiq::Worker.clear_all
    assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    post :create, email: @user.email
    assert_not_equal @user.password_reset_token, @user.reload.password_reset_token
    assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
  end

  test "gets edit" do
    token = @user.generate_token(:password_reset_token, nil, true)
    @user.save
    get :edit, id: token
    assert_response :success
  end

  test "should update password" do
    token = @user.generate_token(:password_reset_token, nil, true)
    @user.password_reset_sent_at = Time.now
    @user.save
    post :update, id: token, user: {password: 'new password'}
    assert_redirected_to login_url
  end

  test "shouldn't update password with expired token" do
    token = @user.generate_token(:password_reset_token, nil, true)
    @user.password_reset_sent_at = 3.hours.ago
    @user.save
    post :update, id: token, user: {password: 'new password'}
    assert_redirected_to new_password_reset_path
    assert flash[:alert].present?
  end

end
