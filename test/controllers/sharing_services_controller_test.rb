require 'test_helper'

class SharingServicesControllerTest < ActionController::TestCase
  setup do
    @sharing_service = sharing_services(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:sharing_services)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create sharing_service" do
    assert_difference('ShareAction.count') do
      post :create, sharing_service: { name: @sharing_service.name, url: @sharing_service.url }
    end

    assert_redirected_to sharing_service_path(assigns(:sharing_service))
  end

  test "should show sharing_service" do
    get :show, id: @sharing_service
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @sharing_service
    assert_response :success
  end

  test "should update sharing_service" do
    patch :update, id: @sharing_service, sharing_service: { name: @sharing_service.name, url: @sharing_service.url }
    assert_redirected_to sharing_service_path(assigns(:sharing_service))
  end

  test "should destroy sharing_service" do
    assert_difference('ShareAction.count', -1) do
      delete :destroy, id: @sharing_service
    end

    assert_redirected_to sharing_services_path
  end
end
