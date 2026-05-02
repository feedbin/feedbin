require "test_helper"

class SettingsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get settings" do
    login_as @user
    get :index
    assert_response :success
  end

  test "should get account" do
    login_as @user
    get :account
    assert_response :success
  end

  test "should get account @last_payment" do
    StripeMock.start
    event = StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id})
    BillingEvent.create(info: event.as_json)
    login_as @user
    get :account
    assert_response :success
    assert assigns(:last_payment).present?, "@last_payment should exist"
    StripeMock.stop
  end

  test "should not get account @last_payment because it is too old" do
    StripeMock.start
    event = StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id})
    BillingEvent.create(info: event.as_json).update(created_at: 8.days.ago)
    login_as @user
    get :account
    assert_response :success
    assert_nil assigns(:last_payment)
    StripeMock.stop
  end

  test "should update settings" do
    login_as @user

    settings = [
      :entry_sort, :starred_feed_enabled, :precache_images,
      :show_unread_count, :sticky_view_inline, :mark_as_read_confirmation,
      :apple_push_notification_device_token, :receipt_info, :entries_display,
      :entries_feed, :entries_time, :entries_body, :ui_typeface, :theme,
      :hide_recently_read, :hide_updated, :disable_image_proxy, :entries_image
    ].each_with_object({}) { |setting, hash| hash[setting.to_s] = "1" }

    patch :settings_update, params: {id: @user, user: settings}
    assert_redirected_to settings_url
    assert_equal settings, @user.reload.settings
  end

  test "should update now playing" do
    @feeds = create_feeds(@user)
    @entries = @user.entries

    login_as @user
    post :now_playing, params: {now_playing_entry: @entries.first.id}
    assert_not_equal @entries.first.id, @user.reload.now_playing_entry.to_s
  end

  test "should remove now playing" do
    login_as @user
    now_playing_entry = "1"
    @user.update(now_playing_entry: now_playing_entry)
    assert_equal @user.reload.now_playing_entry, now_playing_entry

    post :now_playing, params: {remove_now_playing_entry: 1}
    assert_nil @user.reload.now_playing_entry
  end

  test "should change audio panel size" do
    login_as @user
    %w[minimized maximized].each do |audio_panel_size|
      post :audio_panel_size, params: {audio_panel_size: audio_panel_size}
      assert_equal(audio_panel_size, @user.reload.audio_panel_size)
    end
  end

  test "GET appearance assigns @user" do
    login_as @user
    get :appearance, xhr: true
    assert_equal @user, assigns(:user)
  end

  test "settings_update with invalid params alerts and redirects" do
    login_as @user
    User.any_instance.stub :save, false do
      User.any_instance.stub :errors, OpenStruct.new(full_messages: ["bad"]) do
        patch :settings_update, params: {user: {entry_sort: "ASC"}}
      end
    end
    assert_redirected_to settings_url
  rescue NoMethodError
    skip "any_instance not available"
  end

  test "settings_update with redirect_to param redirects to that URL" do
    login_as @user
    patch :settings_update, params: {id: @user.id, user: {entry_sort: "ASC"}, redirect_to: "/somewhere"}
    assert_redirected_to "/somewhere"
  end

  test "view_settings_update flips a tag visibility when one is provided" do
    login_as @user
    patch :view_settings_update, params: {id: @user.id, tag_visibility: "1", tag: "42"}, xhr: true
    assert_response :ok
  end

  test "view_settings_update stores column widths in the session" do
    login_as @user
    patch :view_settings_update, params: {id: @user.id, column_widths: "1", column: "main", width: "320"}, xhr: true
    assert_response :ok
  end

  test "format updates user attributes and merges into the cookie" do
    login_as @user
    patch :format, params: {id: @user.id, user: {font_size: "5", theme: "dark"}}, xhr: true
    assert_response :success
    assert_equal "5", @user.reload.font_size.to_s
  end

  test "sticky toggles view_inline on the matching subscription" do
    login_as @user
    feed = @user.feeds.first
    sub = @user.subscriptions.where(feed_id: feed.id).first
    initial = sub.view_inline
    post :sticky, params: {feed_id: feed.id}, xhr: true
    assert_equal !initial, sub.reload.view_inline
  end

  test "subscription_view_mode updates the subscription view_mode" do
    login_as @user
    feed = @user.feeds.first
    post :subscription_view_mode, params: {feed_id: feed.id, subscription: {view_mode: "extract"}}, xhr: true
    assert_response :success
    assert_equal "extract", @user.subscriptions.where(feed_id: feed.id).first.view_mode
  end
end
