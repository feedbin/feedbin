require "test_helper"

class Settings::Newsletters::SendersControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get index" do
    user = users(:new)
    login_as user

    get :index
    assert_response :success
  end

  test "should update sender" do
    user = users(:new)
    feeds = create_feeds(user)

    login_as user
    token = user.newsletter_authentication_token.token
    sender = NewsletterSender.create!(
      token: token,
      full_token: token,
      email: "example@example.com",
      feed: feeds.first
    )

    assert_difference -> { Subscription.count }, -1 do
      patch :update, params: {id: sender, newsletter_sender: {token: token, active: 0}}, xhr: true
    end

    assert_response :success

    assert_difference -> { Subscription.count }, +1 do
      patch :update, params: {id: sender, newsletter_sender: {token: token, active: 1}}, xhr: true
    end

    assert_equal "Settings updated.", flash[:notice]

    assert_response :success
  end
end
