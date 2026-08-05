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

  test "should not fail when the sender is toggled on twice" do
    user, token, sender = newsletter_sender

    login_as user
    on = {id: sender.id, newsletter_sender: {token: token, active: "1"}}

    patch :update, params: on, xhr: true
    assert_response :success

    assert_no_difference -> { Subscription.count } do
      patch :update, params: on, xhr: true
    end
    assert_response :success
    assert user.subscriptions.where(feed_id: sender.feed_id).exists?
  end

  test "should not fail when the sender is toggled off twice" do
    user, token, sender = newsletter_sender

    login_as user
    off = {id: sender.id, newsletter_sender: {token: token, active: "0"}}

    patch :update, params: off, xhr: true
    assert_response :success

    assert_no_difference -> { Subscription.count } do
      patch :update, params: off, xhr: true
    end
    assert_response :success
    assert_not user.subscriptions.where(feed_id: sender.feed_id).exists?
  end

  test "should not fail when the token does not own the sender" do
    user, _token, sender = newsletter_sender

    login_as user
    patch :update, params: {id: sender.id, newsletter_sender: {token: "not-a-token", active: "1"}}, xhr: true

    assert_response :not_found
  end

  private

  def newsletter_sender
    user = users(:new)
    feeds = create_feeds(user)
    token = user.newsletter_authentication_token.token
    sender = NewsletterSender.create!(
      token: token,
      full_token: token,
      email: "example@example.com",
      feed: feeds.first
    )
    [user, token, sender]
  end
end
