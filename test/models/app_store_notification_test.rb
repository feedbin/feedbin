require "test_helper"

class AppStoreNotificationTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    # 2024-01-15T12:00:00Z in milliseconds since epoch
    @purchase_date_ms = 1705320000000
  end

  def build_notification(product_id:)
    @user.app_store_notifications.create!(
      original_transaction_id: "txn-#{SecureRandom.hex(4)}",
      notification_id: SecureRandom.uuid,
      notification_type: "DID_RENEW",
      version: "2.0",
      data: {
        "data" => {
          "signedTransactionInfo" => {
            "productId" => product_id,
            "purchaseDate" => @purchase_date_ms
          }
        }
      }
    )
  end

  test "plan returns the productId from the signed transaction info" do
    notification = build_notification(product_id: "monthly_pro_v1")
    assert_equal "monthly_pro_v1", notification.plan
  end

  test "receipt_amount is 5.99 for monthly plan" do
    notification = build_notification(product_id: "monthly_pro_v1")
    assert_equal 5.99, notification.receipt_amount
  end

  test "receipt_amount is 59.9 for yearly plan" do
    notification = build_notification(product_id: "yearly_pro_v1")
    assert_equal 59.9, notification.receipt_amount
  end

  test "receipt_amount is nil for an unknown plan" do
    notification = build_notification(product_id: "something_else")
    assert_nil notification.receipt_amount
  end

  test "receipt_description is 'Monthly' for monthly plan" do
    notification = build_notification(product_id: "monthly_pro_v1")
    assert_equal "Monthly", notification.receipt_description
  end

  test "receipt_description is 'Yearly' for yearly plan" do
    notification = build_notification(product_id: "yearly_pro_v1")
    assert_equal "Yearly", notification.receipt_description
  end

  test "receipt_description is nil for an unknown plan" do
    notification = build_notification(product_id: "something_else")
    assert_nil notification.receipt_description
  end

  test "currency is USD" do
    notification = build_notification(product_id: "monthly_pro_v1")
    assert_equal "USD", notification.currency
  end

  test "purchase_date converts the millisecond timestamp into a Time" do
    notification = build_notification(product_id: "monthly_pro_v1")
    assert_equal Time.at(@purchase_date_ms / 1000), notification.purchase_date
  end

  test "ms_to_date converts milliseconds to a Time" do
    notification = build_notification(product_id: "monthly_pro_v1")
    assert_equal Time.at(1705320000), notification.ms_to_date(1705320000000)
  end

  test "receipt_date returns a formatted date string" do
    notification = build_notification(product_id: "monthly_pro_v1")
    expected = Time.at(@purchase_date_ms / 1000).to_formatted_s(:date)
    assert_equal expected, notification.receipt_date
  end
end
