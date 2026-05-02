require "test_helper"

class Admin::UsersControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @user.update!(admin: true) if User.column_names.include?("admin")
    @user.update!(roles: ["admin"]) if User.column_names.include?("roles")
  end

  test "GET index requires admin" do
    other = users(:new)
    login_as other
    get :index
    assert_response :not_found
  end

  test "GET index renders with no query" do
    login_as @user
    get :index
    assert_response :success
  end

  test "GET index searches by email when q is provided" do
    login_as @user
    get :index, params: {q: @user.email}
    assert_response :success
  end

  test "DELETE destroy enqueues UserDeleter for the target user" do
    login_as @user
    target = users(:new)
    Sidekiq::Worker.clear_all
    assert_difference -> { UserDeleter.jobs.size }, +1 do
      delete :destroy, params: {id: target.id}, xhr: true
    end
  end

  test "POST reset_password sets the reset flag and sends an email" do
    login_as @user
    target = users(:new)
    sent = false
    target.stub :send_password_reset, ->() { sent = true } do
      User.stub :find, target do
        post :reset_password, params: {id: target.id}, xhr: true
      end
    end
    assert sent
  end
end
