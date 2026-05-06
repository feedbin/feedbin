require "test_helper"

class Api::V2::SubscriptionsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success

    get :index, format: :xml
    assert_response :success
  end

  test "should show subscription" do
    login_as @user
    get :index, params: {id: @user.subscriptions.first}, format: :json
    assert_response :success
  end

  test "should create subscription" do
    api_content_type

    html_url = "www.example.com/index.html"
    stub_request_file("index.html", html_url)
    stub_request_file("atom.xml", "www.example.com/atom.xml")

    login_as @user
    assert_difference "Subscription.count", +1 do
      post :create, params: {feed_url: html_url}, format: :json
      assert_response :success
    end
  end

  test "should update subscription" do
    login_as @user
    subscription = @user.subscriptions.first

    attributes = {title: "#{@user.subscriptions.first} new"}
    patch :update, params: {id: subscription, subscription: attributes}, format: :json

    assert_response :success
    attributes.each do |attribute, value|
      assert_equal(value, subscription.reload.send(attribute))
    end
  end

  test "should return 400 on malformed JSON body" do
    api_content_type
    login_as @user

    notifications = []
    ErrorService.stub :notify, ->(exception) { notifications << exception } do
      post :create, body: "{not valid json", format: :json
    end

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal 400, body["status"]
    assert_equal "Problem parsing JSON", body["message"]
    assert_equal 1, notifications.size
  end
end
