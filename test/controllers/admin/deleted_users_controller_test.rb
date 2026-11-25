require "test_helper"

class Admin::DeletedUsersControllerTest < ActionController::TestCase
  setup do
    @admin = users(:ben)
    @admin.update!(admin: true)
    @deleted = DeletedUser.create!(email: "gone@example.com", customer_id: "cus_gone", original_user_id: 999_001,
      store_subscriptions: [{"store" => "apple", "external_id" => "2000000700000001", "product_id" => "monthly_pro_v1"}])
  end

  test "GET show requires admin" do
    login_as users(:new)
    get :show, params: {id: @deleted.id}
    assert_response :not_found
  end

  test "GET show says what a store may still be billing, and what Apple said since" do
    AppStoreNotification.create!(original_transaction_id: "2000000700000001", notification_id: SecureRandom.uuid, notification_type: "DID_RENEW",
      version: "2.0", processed_at: Time.now, data: {"data" => {"signedTransactionInfo" => {"productId" => "monthly_pro_v1"}}})
    login_as @admin

    get :show, params: {id: @deleted.id}

    assert_response :success
    assert_includes response.body, "gone@example.com"
    assert_includes response.body, "Closed account"
    assert_includes response.body, "Had a subscription with App Store"
    assert_includes response.body, "2000000700000001"
    assert_includes response.body, "It is emailed once if the store charges again"
    assert_includes response.body, "Recent Apple Events"
    assert_includes response.body, "Did Renew"
    assert_includes response.body, "no account"
    assert_select "a[href=?]", @deleted.stripe_url
  end
end
