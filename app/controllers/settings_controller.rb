class SettingsController < ApplicationController

  before_action :plan_exists, only: [:update_plan]

  def settings
    @user = current_user
  end

  def account
    @user = current_user
  end

  def appearance
    @user = current_user
    @classes = user_classes
  end

  def feeds
    @user = current_user
    @subscriptions = @user.subscriptions.select('subscriptions.*, feeds.title AS original_title, feeds.last_published_entry AS last_published_entry, feeds.feed_url, feeds.site_url, feeds.host').joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}").includes(feed: [:favicon])

    start_date = 29.days.ago
    feed_ids = @subscriptions.map {|subscription| subscription.feed_id}
    entry_counts = Rails.cache.fetch("#{@user.id}:entry_counts:2", expires_in: 24.hours) { FeedStat.get_entry_counts(feed_ids, start_date) }

    @subscriptions = @subscriptions.map do |subscription|
      counts = entry_counts[subscription.feed_id]
      max = (counts.present?) ? counts.max.to_i : 0
      percentages = (counts.present?) ? counts.map { |count| count.to_f / max.to_f } : nil
      volume = (counts.present?) ? counts.sum : 0

      subscription.entries_count = percentages
      subscription.post_volume = volume

      if subscription.title
        subscription.title = subscription.title
      elsif subscription.original_title
        subscription.title = subscription.original_title
      else
        subscription.title = '(No title)'
      end
      subscription
    end

    @subscriptions = @subscriptions.sort_by {|subscription| subscription.title.downcase}
  end

  def billing
    @user = current_user

    @default_plan = Plan.where(price_tier: @user.price_tier, stripe_id: ['basic-yearly-2', 'basic-yearly-3']).first

    @next_payment = @user.billing_events.where(event_type: 'invoice.payment_succeeded')
    @next_payment = @next_payment.to_a.sort_by {|next_payment| -next_payment.event_object["date"] }
    if @next_payment.present?
      @next_payment.first.event_object["lines"]["data"].each do |event|
        if event.dig("type") == 'subscription'
          @next_payment_date = Time.at(event["period"]["end"]).utc.to_datetime
        end
      end
    end

    if @user.plan.stripe_id == "timed"
      @billing_events = @user.in_app_purchases.order(purchase_date: :desc)
    else
      @billing_events = @user.billing_events.where(event_type: 'charge.succeeded')
      @billing_events = @billing_events.to_a.sort_by {|billing_event| -billing_event.event_object["created"] }
    end
    @plans = @user.available_plans
  end

  def import_export
    @user = current_user
    @uploader = Import.new.upload
    @uploader.success_action_redirect = settings_import_export_url
    @tags = @user.feed_tags

    @download_options = @tags.map do |tag|
      [tag.name, tag.id]
    end

    @download_options.unshift(['All', 'all'])

    if params[:key]
      @import = Import.new(key: params[:key], user: @user)

      if @import.save
        redirect_to settings_import_export_url, notice: 'Import has started.'
      else
        @messages = @import.errors.full_messages
        flash[:error] = render_to_string partial: "shared/messages"
        redirect_to settings_import_export_url
      end
    end
  end

  def update_plan
    @user = current_user
    plan = Plan.find(params[:plan])
    @user.plan = plan
    @user.save
    redirect_to settings_billing_path, notice: 'Plan successfully changed.'
  rescue Stripe::CardError
    redirect_to settings_billing_path, alert: "Your card was declined, please update your billing information."
  end

  def update_credit_card
    @user = current_user

    if params[:stripe_token].present?
      @user.stripe_token = params[:stripe_token]
      if @user.save
        customer = Customer.retrieve(@user.customer_id)
        customer.reopen_account if customer.unpaid?
        redirect_to settings_billing_url, notice: 'Your credit card has been updated.'
      else
        redirect_to settings_billing_url, alert: @user.errors.messages[:base].join(' ')
      end
    else
      redirect_to settings_billing_url, alert: 'There was a problem updating your credit card. Please try again.'
      Librato.increment('billing.token_missing')
    end

  end

  def settings_update
    @user = current_user
    @user.attributes = user_settings_params
    if @user.save
      respond_to do |format|
        flash[:notice] = 'Settings updated.'
        format.js {flash.discard()}
        format.html do
          if params[:redirect_to]
            redirect_to params[:redirect_to]
          else
            redirect_to settings_url
          end
        end
      end
    else
      respond_to do |format|
        flash[:alert] = @user.errors.full_messages.join('. ') + '.'
        format.js {flash.discard()}
        format.html do
          redirect_to settings_url
        end
      end
    end
  end

  def view_settings_update
    @user = current_user
    if params[:tag_visibility]
      tag_id = params[:tag].to_s
      if @user.tag_visibility[params[:tag]].blank?
        @user.update_tag_visibility(tag_id, true)
      else
        @user.update_tag_visibility(tag_id, false)
      end
    end

    if params[:column_widths]
      session[:column_widths] ||= {}
      session[:column_widths][params[:column]] = params[:width]
    end
    head :ok
  end

  def font_increase
    change_font_size('increase')
  end

  def font_decrease
    change_font_size('decrease')
  end

  def font
    @user = current_user
    if Feedbin::Application.config.fonts.has_value?(params[:font])
      @user.font = params[:font]
      @user.save
    end
    head :ok
  end

  def theme
    @user = current_user
    themes = ['day', 'night', 'sunset']
    if themes.include?(params[:theme])
      @user.theme = params[:theme]
      @user.save
    end
    head :ok
  end

  def entry_width
    @user = current_user
    if @user.entry_width.blank?
      new_width = 'fluid'
    else
      new_width = ''
    end
    @user.entry_width = new_width
    @user.save
    head :ok
  end

  def now_playing
    user = current_user
    if params[:now_playing_entry]
      entry_id = params[:now_playing_entry].to_i
      if user.can_read_entry?(entry_id)
        user.update(now_playing_entry: entry_id)
      end
    end

    if params[:remove_now_playing_entry]
      user.update(now_playing_entry: nil)
    end
    head :ok
  end

  def audio_panel_size
    user = current_user
    if %w{minimized maximized}.include?(params[:audio_panel_size])
      user.update(audio_panel_size: params[:audio_panel_size])
    end
    head :ok
  end

  private

  def change_font_size(direction)
    @user = current_user

    current_font_size = @user.font_size.try(:to_i) || 5
    if direction == 'increase'
      new_font_size = current_font_size + 1
    else
      new_font_size = current_font_size - 1
    end

    if Feedbin::Application.config.font_sizes[new_font_size] && new_font_size >= 0
      @user.font_size = new_font_size
      @user.save
    end

    head :ok
  end

  def plan_exists
    render_404 unless Plan.exists?(params[:plan].to_i)
  end

  def user_settings_params
    params.require(:user).permit(:entry_sort, :starred_feed_enabled, :precache_images,
                                 :show_unread_count, :sticky_view_inline, :mark_as_read_confirmation,
                                 :apple_push_notification_device_token, :receipt_info, :entries_display,
                                 :entries_feed, :entries_time, :entries_body, :ui_typeface, :theme,
                                 :hide_recently_read, :hide_updated, :disable_image_proxy, :entries_image,
                                 :now_playing_entry)
  end

  def user_now_playing_params
    params.require(:user).permit(:now_playing_entry)
  end


end
