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
end
