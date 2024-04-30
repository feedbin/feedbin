require "test_helper"

class Settings::Newsletters::AddressesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should show address" do
    user = users(:new)
    login_as user

    get :show, params: {id: user.newsletter_authentication_token}
    assert_response :success
  end

  test "should show new" do
    user = users(:new)
    login_as user

    get :new
    assert_response :success
  end

  test "should update" do
    user = users(:new)
    login_as user

    description = "Description"
    newsletter_tag = "Newsletters"

    feeds = create_feeds(user)
    feeds.first.tag(newsletter_tag, @user)

    token = user.newsletter_authentication_token

    patch :update, params: {id: token, authentication_token: {description: description, newsletter_tag: newsletter_tag}}, xhr: true
    assert_response :success

    assert_equal(description, token.reload.description)
    assert_equal(newsletter_tag, token.reload.newsletter_tag)
  end

  test "should destroy" do
    user = users(:new)
    login_as user

    token = user.newsletter_authentication_token

    delete :destroy, params: {id: token}, xhr: true

    assert_not token.reload.active?
  end

  test "should activate" do
    user = users(:new)
    login_as user

    token = user.newsletter_authentication_token
    token.update(active: false)

    patch :activate, params: {id: token}, xhr: true

    assert token.reload.active?
  end

  test "should show inactive" do
    user = users(:new)
    login_as user

    token = user.newsletter_authentication_token
    token.update(active: false)

    get :inactive

    assert_response :success
  end

  test "should create random" do
    user = users(:new)
    login_as user

    assert_difference -> {AuthenticationToken.count}, +1 do
      post :create, params: {button_action: "save", authentication_token: {type: "random"}}, xhr: true
    end

    assert_response :success
    assert assigns(:address).newsletters?
  end

  test "should create custom" do
    user = users(:new)
    login_as user

    token_name = "my.token"
    verified_token = Rails.application.message_verifier(:address_token).generate(token_name)

    assert_difference -> {AuthenticationToken.count}, +1 do
      post :create, params: {button_action: "save", authentication_token: {verified_token: verified_token}}, xhr: true
    end

    assert_response :success
    assert_equal token_name, assigns(:address).token
  end

  test "should preview custom" do
    user = users(:new)
    login_as user

    post :create, params: {authentication_token: {type: "custom", token: "I@nva-li.d_ + token"}}, xhr: true

    assert_response :success

    assert_equal("inva-li.d_token.#{assigns(:numbers)}", assigns(:token))
    assert assigns(:token)
    assert assigns(:numbers)
    assert assigns(:message)
  end
end
