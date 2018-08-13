require "test_helper"

class SupportedSharingServicesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @service = @user.supported_sharing_services.create(service_id: "kindle")
  end

  test "should create supported sharing service" do
    login_as @user
    assert_difference "SupportedSharingService.count", +1 do
      post :create, params: {supported_sharing_service: {service_id: "email"}}
      assert_redirected_to sharing_services_url
    end
  end

  test "should destroy supported sharing service" do
    login_as @user
    assert_difference "SupportedSharingService.count", -1 do
      delete :destroy, params: {id: @service}
      assert_redirected_to sharing_services_url
    end
  end

  test "should update supported sharing service" do
    login_as @user
    attributes = {email_name: "email_name", email_address: "email_address", kindle_address: "kindle_address"}
    patch :update, params: {id: @service, supported_sharing_service: attributes}
    assert_redirected_to sharing_services_url
    attributes.each do |attribute, value|
      assert_equal(value, @service.reload.send(attribute))
    end
  end

  test "should get completions" do
    options = ["test@test.com", "test@example.com"]
    @service.update(service_options: {completions: options})
    login_as @user
    get :autocomplete, params: {id: @service, query: "test"}
    assert_response :success
    data = JSON.parse(@response.body)
    assert data.length, options.length
  end

  test "should authorize with oauth" do
    code = "code"
    token = "access_token"

    stub_request(:post, Share::Pocket.new.url_for(:oauth_request).to_s).
      to_return(body: {code: code}.to_json, status: 200)

    login_as @user
    post :create, params: {supported_sharing_service: {service_id: "pocket", operation: "authorize"}}
    assert_redirected_to Share::Pocket.new.authorize_url(code)

    stub_request(:post, Share::Pocket.new.url_for(:oauth_authorize).to_s).
      with(body: hash_including({"code" => code})).
      to_return(body: {access_token: token}.to_json, status: 200)

    assert_difference "SupportedSharingService.count", +1 do
      get :oauth_response, params: {id: "pocket"}
      assert_redirected_to sharing_services_url
    end

    pocket = @user.supported_sharing_services.where(service_id: "pocket").take
    assert_equal token, pocket.settings["access_token"]
  end

  test "should share" do
    Sidekiq::Worker.clear_all
    @service.update(kindle_address: "example@example.com")
    login_as @user
    assert_difference "SendToKindle.jobs.size", +1 do
      post :share, params: {id: @service, entry_id: 1}, xhr: true
      assert_response :success
    end
  end
end
