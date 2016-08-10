require 'test_helper'

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
    get :index, id: @user.subscriptions.first, format: :json
    assert_response :success
  end

  test "should create subscription" do
    api_content_type
    html_file = File.join(Rails.root, "test/support/www/index.html")
    html_url = "www.example.com/index.html"
    stub_request(:get, html_url).
      to_return(body: File.new(html_file), status: 200)

    xml_file = File.join(Rails.root, "test/support/www/atom.xml")
    stub_request(:get, "www.example.com/atom.xml").
      to_return(body: File.new(xml_file), status: 200)

    login_as @user
    assert_difference "Subscription.count", +1 do
      post :create, feed_url: html_url, format: :json
      assert_response :success
    end
  end

  test "should update subscription" do
    login_as @user
    subscription = @user.subscriptions.first

    attributes = {title: "#{@user.subscriptions.first} new"}
    patch :update, id: subscription, subscription: attributes, format: :json

    assert_response :success
    attributes.each do |attribute, value|
      assert_equal(value, subscription.reload.send(attribute))
    end
  end

end
