class SettingsController < ApplicationController

  before_action :plan_exists, only: [:update_plan]

  def help
    @user = current_user
  end

  def settings
    @user = current_user
  end

  def sharing
    @user = current_user
  end

  def account
    @user = current_user
  end

  def feeds
    @user = current_user
    @subscriptions = @user.subscriptions.select('subscriptions.*, feeds.title AS original_title, feeds.feed_url, feeds.site_url').joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}")
    @subscriptions = @subscriptions.map {|subscription|
      if subscription.title
        subscription.title = subscription.title
      elsif subscription.original_title
        subscription.title = subscription.original_title
      else
        subscription.title = '(No title)'
      end
      subscription
    }
    @subscriptions = @subscriptions.sort_by {|subscription| subscription.title.downcase}

    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    @authentication_token = CGI::escape(verifier.generate(@user.id))
    @web_service_url = "#{ENV['PUSH_URL']}/apple_push_notifications"
  end

  def billing
    @user = current_user
    @next_payment = @user.billing_events.where(event_type: 'invoice.payment_succeeded')
    @next_payment = @next_payment.to_a.sort_by {|next_payment| -next_payment.details.data.object.date }
    if @next_payment.present?
      @next_payment.first.details.data.object.lines.data.each do |event|
        event = event.to_hash
        if event[:type] && event[:type] == 'subscription'
          @next_payment = Time.at(event[:period].end).utc.to_datetime
        end
      end
    end
    @billing_events = @user.billing_events.where(event_type: 'charge.succeeded')
    @billing_events = @billing_events.to_a.sort_by {|billing_event| -billing_event.details.data.object.created }
    if @user.plan.stripe_id == 'free'
      @plans = Plan.where(price_tier: @user.plan.price_tier)
    else
      @plans = Plan.where(price_tier: @user.plan.price_tier).where.not(stripe_id: ['free', 'trial'])
    end
  end

  def import_export
    @user = current_user
    @uploader = Import.new.upload
    @uploader.success_action_redirect = settings_import_export_url

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

  def mark_favicon_complete
    session[:favicon_complete] = true
    render nothing: true
  end

  def update_plan
    plan = Plan.find(params[:plan])
    @user = current_user
    @user.plan = plan
    @user.save
    customer = Stripe::Customer.retrieve(@user.customer_id)
    customer.update_subscription(plan: plan.stripe_id)
    redirect_to settings_billing_path
  end

  def update_credit_card
    @user = current_user
    @user.stripe_token = params[:stripe_token]
    @user.free_ok = (@user.plan.stripe_id == 'free')

    respond_to do |format|
      if @user.save
        format.html { redirect_to settings_billing_url, notice: 'Your credit card has been updated.' }
      else
        format.html { redirect_to settings_billing_url, alert: @user.errors.messages[:base].join(' ') }
      end
    end
  end

  def settings_update
    @user = current_user
    @user.attributes = user_settings_params
    @user.free_ok = (@user.plan.stripe_id == 'free')
    if @user.save
      if params[:redirect_to]
        redirect_to params[:redirect_to], notice: 'Settings updated.'
      else
        redirect_to settings_path, notice: 'Settings updated.'
      end
    else
      redirect_to settings_path, alert: @user.errors.full_messages.join('. ') + '.'
    end
  end

  def view_settings_update
    if params[:tag_visibility]
      session[:tag_visibility] ||= {}
      tag_id = params[:tag].to_s
      if session[:tag_visibility][params[:tag]].blank?
        session[:tag_visibility][tag_id] = true
      else
        session[:tag_visibility][tag_id] = false
      end
    end

    if params[:column_widths]
      session[:column_widths] ||= {}
      session[:column_widths][params[:column]] = params[:width]
    end
    render nothing: true
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
    render nothing: true
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
    render nothing: true
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

    render nothing: true
  end

  def plan_exists
    render_404 unless Plan.exists?(params[:plan].to_i)
  end

  def user_settings_params
    params.require(:user).permit(:entry_sort, :starred_feed_enabled, :hide_tagged_feeds, :precache_images, :show_unread_count, :sticky_view_inline, :mark_as_read_confirmation, :apple_push_notification_device_token, :receipt_info)
  end

end
