require "test_helper"

class SharingServicesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @services = {
      custom: @user.sharing_services.create(label: "Twitter", url: "${source}${url}${title}"),
      supported: @user.supported_sharing_services.create(service_id: "email"),
    }
  end

  test "should get index" do
    login_as @user
    get :index
    assert_response :success
    assert_equal @services.length, assigns(:active_sharing_services).length
  end

  test "should create sharing service" do
    login_as @user
    assert_difference "SharingService.count", 1 do
      post :create, params: {sharing_service: {label: "Label", url: "URL"}}
      assert_redirected_to sharing_services_url
    end
  end

  test "should destroy sharing service" do
    login_as @user
    sharing_service = @services[:custom]
    assert_difference "SharingService.count", -1 do
      delete :destroy, params: {id: sharing_service}
      assert_redirected_to sharing_services_url
    end
  end

  test "should update sharing service" do
    login_as @user
    sharing_service = @services[:custom]
    attributes = {label: "#{sharing_service.label} new", url: "#{sharing_service.url} new"}
    patch :update, params: {id: sharing_service, sharing_service: attributes}
    assert_redirected_to sharing_services_url
    attributes.each do |attribute, value|
      assert_equal(value, sharing_service.reload.send(attribute))
    end
  end
end
