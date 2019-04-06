require "test_helper"

include CarrierWaveDirect::Test::Helpers

class SettingsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get settings" do
    login_as @user
    get :settings
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

  test "should get appearance" do
    login_as @user
    get :appearance
    assert_response :success
  end

  test "should get billing" do
    StripeMock.start
    events = [
      StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id}),
      StripeMock.mock_webhook_event("invoice.payment_succeeded", {customer: @user.customer_id}),
    ]
    events.each do |event|
      BillingEvent.create(info: event.as_json)
    end

    login_as @user
    get :billing

    assert_response :success
    assert_not_nil assigns(:next_payment_date)
    assert assigns(:billing_events).present?
    StripeMock.stop
  end

  test "should get import_export" do
    login_as @user
    get :import_export
    assert_response :success
  end

  test "should import" do
    login_as @user
    skip "Figure out how to test CarrierWave direct"
    get :import_export, params: {key: sample_key(ImportUploader.new, base: "test.opml")}
    assert_redirected_to settings_import_export_url
  end

  test "should update plan" do
    StripeMock.start
    stripe_helper = StripeMock.create_test_helper

    plans = {
      original: plans(:basic_monthly_3),
      new: plans(:basic_yearly_3),
    }
    plans.each do |_, plan|
      create_stripe_plan(plan)
    end

    customer = Stripe::Customer.create({email: @user.email, plan: plans[:original].stripe_id, source: stripe_helper.generate_card_token})
    @user.update(customer_id: customer.id)
    @user.reload.inspect

    login_as @user
    post :update_plan, params: {plan: plans[:new].id}
    assert_equal plans[:new], @user.reload.plan
    StripeMock.stop
  end

  test "should update credit card" do
    StripeMock.start
    plan = plans(:trial)
    last4 = "1234"
    card_1 = StripeMock.generate_card_token(last4: "4242", exp_month: 99, exp_year: 3005)
    card_2 = StripeMock.generate_card_token(last4: last4, exp_month: 99, exp_year: 3005)
    create_stripe_plan(plan)

    user = User.create(
      email: "cc@example.com",
      password: default_password,
      plan: plan,
    )
    user.stripe_token = card_1
    user.save

    login_as user
    post :update_credit_card, params: {stripe_token: card_2}
    assert_redirected_to settings_billing_url

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert_equal last4, customer.sources.data.first.last4
    StripeMock.stop
  end

  test "should update settings" do
    login_as @user

    settings = [
      :entry_sort, :starred_feed_enabled, :precache_images,
      :show_unread_count, :sticky_view_inline, :mark_as_read_confirmation,
      :apple_push_notification_device_token, :receipt_info, :entries_display,
      :entries_feed, :entries_time, :entries_body, :ui_typeface, :theme,
      :hide_recently_read, :hide_updated, :disable_image_proxy, :entries_image,
    ].each_with_object({}) { |setting, hash| hash[setting.to_s] = "1" }

    patch :settings_update, params: {id: @user, user: settings}
    assert_redirected_to settings_url
    assert_equal settings, @user.reload.settings
  end

  test "should update view settings" do
    login_as @user
    tag = @user.feeds.first.tag("tag", @user).first.tag
    params = {
      id: @user,
      tag_visibility: true,
      tag: tag.id,
      column_widths: true,
      column: "test",
      width: 1234,
    }
    patch :view_settings_update, params: params
    assert_equal({tag.id.to_s => true}, @user.reload.tag_visibility)
    assert_response :success
    assert_equal session[:column_widths], {params[:column] => params[:width].to_s}
  end

  test "should increase font" do
    @user.font_size = 7
    @user.save
    login_as @user

    post :font_increase
    assert_response :success
    assert_equal (@user.font_size.to_i + 1).to_s, @user.reload.font_size
  end

  test "should decrease font" do
    @user.font_size = 7
    @user.save
    login_as @user

    post :font_decrease
    assert_response :success
    assert_equal (@user.font_size.to_i - 1).to_s, @user.reload.font_size
  end

  test "should change font" do
    login_as @user
    post :font, params: {font: Feedbin::Application.config.fonts.values.last}
    assert_equal @user.reload.font, Feedbin::Application.config.fonts.values.last
  end

  test "should change theme" do
    login_as @user
    ["day", "dusk", "sunset", "midnight"].each do |theme|
      post :theme, params: {theme: theme}
      assert_equal(theme, @user.reload.theme)
    end
  end

  test "should change entry width" do
    login_as @user
    post :entry_width
    assert_not_equal @user.entry_width, @user.reload.entry_width
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

  test "view modes" do
    login_as @user

    %w[view_unread view_starred view_all].each do |view_mode|
      get :view_mode, xhr: true, params: {mode: view_mode}
      assert_response :success
      assert_equal view_mode, @user.reload.view_mode
    end
  end

end
