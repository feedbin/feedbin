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

  # Relation#+ is Array#+: it loads both relations and hands the view a plain
  # Array, so the pagination metadata is gone and the page simply ends. On a
  # production table that silently hides every account past the first screen.
  test "GET index gives the view something it can paginate" do
    login_as @user
    get :index
    assert_respond_to assigns(:users), :total_pages
  end

  test "GET index treats a percent in the search as a literal" do
    login_as @user
    users(:new).update_columns(email: "wildcard%test@example.com")

    get :index, params: {q: "%"}

    assert_response :success
    assert_equal 1, assigns(:users).count
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
    assert target.reload.setting_on?(:password_resettable)
  end

  test "GET show requires admin" do
    login_as users(:new)
    get :show, params: {id: users(:ann).id}
    assert_response :not_found
  end

  test "GET show says who bills a web customer, and links to Stripe" do
    login_as @user
    target = users(:new)

    get :show, params: {id: target.id}

    assert_response :success
    assert_select "h1", text: /new@example.com/
    assert_includes response.body, "Feedbin, by card (Stripe)"
    assert_select "a[href=?]", target.stripe_url
  end

  test "GET show lays out a store subscriber's subscription and what Apple has said" do
    login_as @user
    target = users(:ann)
    state = AppStore::SubscriptionState.new(
      transaction: {"originalTransactionId" => "2000000712345678", "bundleId" => "com.feedbin.feedbin.app", "productId" => "yearly_pro_v1",
                    "expiresDate" => 6.months.from_now.to_i * 1000, "signedDate" => Time.now.to_i * 1000, "price" => 70_000, "currency" => "USD"},
      renewal: {"autoRenewStatus" => 0}
    )
    StripeMock.start
    Plan.all.each { create_stripe_plan(_1) rescue nil }
    target.update_column(:customer_id, Stripe::Customer.create(email: target.email, plan: target.plan.stripe_id).id)
    StoreSubscription.record(state, user: target)
    target.app_store_notifications.create!(original_transaction_id: "2000000712345678", notification_id: SecureRandom.uuid, notification_type: "DID_CHANGE_RENEWAL_STATUS",
      subtype: "AUTO_RENEW_DISABLED", version: "2.0", processed_at: Time.now, data: {"data" => {"signedTransactionInfo" => {"productId" => "yearly_pro_v1", "purchaseDate" => Time.now.to_i * 1000}}})

    get :show, params: {id: target.id}

    assert_response :success
    assert_includes response.body, "App Store"
    assert_includes response.body, "Active, renewal off, ends"
    assert_includes response.body, "2000000712345678"
    assert_includes response.body, "70.00 USD"
    assert_includes response.body, "Did Change Renewal Status / Auto Renew Disabled"
    assert_includes response.body, "only its owner can cancel"
  ensure
    StripeMock.stop
  end

  test "GET index links each customer to their page, not to Stripe" do
    login_as @user
    get :index
    assert_select "a[href=?]", admin_user_path(users(:new))
    assert_select "a[href=?]", users(:new).stripe_url, count: 0
  end
end
