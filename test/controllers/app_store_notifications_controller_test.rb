require "test_helper"

class AppStoreNotificationsControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
  end

  test "show finds the notification when it belongs to the user" do
    notification = @user.app_store_notifications.create!(
      original_transaction_id: "tx-1",
      notification_id: SecureRandom.uuid,
      notification_type: "DID_RENEW",
      version: "2.0",
      data: {
        "data" => {
          "signedTransactionInfo" => {
            "productId" => "monthly_pro_v1",
            "purchaseDate" => 1705320000000
          }
        }
      }
    )

    login_as @user
    get :show, params: {id: notification.id}
    assert_response :success
    assert_equal notification, assigns(:billing_event)
  end

  test "show raises RecordNotFound when the notification does not belong to the user" do
    login_as @user
    assert_raises(ActiveRecord::RecordNotFound) do
      get :show, params: {id: 999_999}
    end
  end
end
