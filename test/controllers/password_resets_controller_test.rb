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

    # should not allow twice in a row
    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      assert_no_difference -> { @user.password_reset_sent_at } do
        Sidekiq::Testing.inline! do
          post :create, params: {email: @user.email}
        end
      end
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

  test "trial user without turnstile env sees email message" do
    user = users(:ann)
    ENV.delete("TURNSTILE_SITE_KEY")
    ENV.delete("TURNSTILE_SECRET_KEY")
    post :create, params: {email: user.email}
    assert_redirected_to login_url
    assert_match /Email.*to request a password reset/, flash[:notice]
  ensure
    ENV["TURNSTILE_SITE_KEY"] = "test-site-key"
    ENV["TURNSTILE_SECRET_KEY"] = "test-secret-key"
  end

  test "trial user with turnstile env and no token sees challenge" do
    user = users(:ann)
    post :create, params: {email: user.email}
    assert_response :success
    assert_match /Checking/, response.body
  end

  test "trial user with valid turnstile token sends password reset" do
    user = users(:ann)
    stub_request(:post, Turnstile::VERIFY_URL).to_return(
      body: {success: true}.to_json,
      headers: {"Content-Type" => "application/json"}
    )
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        post :create, params: {email: user.email, "cf-turnstile-response" => "valid-token"}
      end
    end
    assert_redirected_to login_url
    assert_equal "Email sent with password reset instructions.", flash[:notice]
  end

  test "trial user with failed turnstile verification sees email message" do
    user = users(:ann)
    stub_request(:post, Turnstile::VERIFY_URL).to_return(
      body: {success: false}.to_json,
      headers: {"Content-Type" => "application/json"}
    )
    assert_no_difference "ActionMailer::Base.deliveries.count" do
      Sidekiq::Testing.inline! do
        post :create, params: {email: user.email, "cf-turnstile-response" => "bad-token"}
      end
    end
    assert_redirected_to login_url
    assert_match /Email.*to request a password reset/, flash[:notice]
  end

  test "non-trial user bypasses turnstile entirely" do
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        post :create, params: {email: @user.email}
      end
    end
    assert_redirected_to login_url
    assert_equal "Email sent with password reset instructions.", flash[:notice]
  end

  test "unknown email bypasses turnstile entirely" do
    assert_no_difference "ActionMailer::Base.deliveries.count" do
      post :create, params: {email: "unknown@example.com"}
    end
    assert_redirected_to login_url
    assert_equal "Email sent with password reset instructions.", flash[:notice]
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
