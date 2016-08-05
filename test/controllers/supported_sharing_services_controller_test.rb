require 'test_helper'

class SupportedSharingServicesControllerTest < ActionController::TestCase

  setup do
    @user = users(:ben)
    @service = @user.supported_sharing_services.create(service_id: 'kindle')
  end

  test "should create supported sharing service" do
    login_as @user
    assert_difference "SupportedSharingService.count", +1 do
      post :create, supported_sharing_service: {service_id: 'email'}
      assert_redirected_to sharing_services_url
    end
  end

  test "should destroy supported sharing service" do
    login_as @user
    assert_difference "SupportedSharingService.count", -1 do
      delete :destroy, id: @service
      assert_redirected_to sharing_services_url
    end
  end

  test "should update supported sharing service" do
    login_as @user
    attributes = {email_name: 'email_name', email_address: 'email_address', kindle_address: 'kindle_address'}
    patch :update, id: @service, supported_sharing_service: attributes
    assert_redirected_to sharing_services_url
    attributes.each do |attribute, value|
      assert_equal(value, @service.reload.send(attribute))
    end
  end

  test "should get completions" do
    options = ['test@test.com', 'test@example.com']
    @service.update(service_options: {completions: options})
    login_as @user
    get :autocomplete, id: @service, query: 'test'
    assert_response :success
    data = JSON.parse(@response.body)
    assert data.length, options.length
  end

  test "should authorize with pocket" do

  end

end