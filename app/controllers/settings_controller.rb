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

  def appearance
    @user = current_user
    @classes = user_classes
  end

  def feeds
    @user = current_user
    @subscriptions = @user.subscriptions.select('subscriptions.*, feeds.title AS original_title, feeds.last_published_entry AS last_published_entry, feeds.feed_url, feeds.site_url, feeds.host').joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}").includes(:feed)

    start_date = 29.days.ago
    feed_ids = @subscriptions.map {|subscription| subscription.feed_id}
    entry_counts = Rails.cache.fetch("#{@user.id}:entry_counts:2", expires_in: 24.hours) { get_entry_counts(feed_ids, start_date) }
    max = Rails.cache.fetch("#{@user.id}:max_entry_count", expires_in: 24.hours) { max_entry_count(feed_ids, start_date) }

    @subscriptions = @subscriptions.map do |subscription|
      counts = entry_counts[subscription.feed_id]
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
    @next_payment = @user.billing_events.where(event_type: 'invoice.payment_succeeded')
    @next_payment = @next_payment.to_a.sort_by {|next_payment| -next_payment.details.data.object.date }
    if @next_payment.present?
      @next_payment.first.details.data.object.lines.data.each do |event|
        event = event.to_hash
        if event[:type] && event[:type] == 'subscription'
          @next_payment_date = Time.at(event[:period].end).utc.to_datetime
        end
      end
    end
    @billing_events = @user.billing_events.where(event_type: 'charge.succeeded')
    @billing_events = @billing_events.to_a.sort_by {|billing_event| -billing_event.details.data.object.created }
    if @user.plan.stripe_id == 'trial'
      @plans = Plan.where(stripe_id: ['basic-monthly-2', 'basic-yearly-2']).order('id DESC')
    elsif @user.plan.stripe_id == 'free'
      @plans = Plan.where(price_tier: @user.plan.price_tier)
    else
      @plans = Plan.where(price_tier: @user.plan.price_tier).where.not(stripe_id: ['free', 'trial', 'timed'])
    end
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

  def mark_favicon_complete
    session[:favicon_complete] = true
    render nothing: true
  end

  def update_plan
    @user = current_user
    plan = Plan.find(params[:plan])
    customer = Stripe::Customer.retrieve(@user.customer_id)
    customer.update_subscription(plan: plan.stripe_id)
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

  def theme
    @user = current_user
    themes = ['day', 'night', 'sunset']
    if themes.include?(params[:theme])
      @user.theme = params[:theme]
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
    params.require(:user).permit(:entry_sort, :starred_feed_enabled, :precache_images,
                                 :show_unread_count, :sticky_view_inline, :mark_as_read_confirmation,
                                 :apple_push_notification_device_token, :receipt_info, :entries_display,
                                 :entries_feed, :entries_time, :entries_body, :ui_typeface, :theme,
                                 :hide_recently_read, :hide_updated, :disable_image_proxy)
  end

  def get_entry_counts(feed_ids, start_date)
    end_date = Time.now

    stats_query = relative_entry_count_query

    entry_counts = {}
    feed_ids.each do |feed_id|
      query = ActiveRecord::Base.send(:sanitize_sql_array, [stats_query, start_date, end_date, start_date, feed_id])
      results = ActiveRecord::Base.connection.execute(query)
      results.each do |result|
        if entry_counts.has_key?(feed_id)
          entry_counts[feed_id] << result['entries_count'].to_i
        else
          entry_counts[feed_id] = [result['entries_count'].to_i]
        end
      end
    end
    entry_counts
  end

  def max_entry_count(feed_ids, start_date)
    max_query = "SELECT COALESCE(MAX(entries_count), 0) as max FROM feed_stats WHERE feed_id IN(?) and day >= ?"
    max_query = ActiveRecord::Base.send(:sanitize_sql_array, [max_query, feed_ids, start_date])
    max = ActiveRecord::Base.connection.execute(max_query)
    max.first['max'].to_i
  end

  def relative_entry_count_query
    <<-eos
      SELECT
        date,
        coalesce(entries_count,0) AS entries_count
      FROM
      generate_series(
        ?::date,
        ?::date,
        '1 day'
      ) AS date
      LEFT OUTER JOIN (
        SELECT
        day,
        entries_count
        FROM feed_stats
        WHERE day >= ?
        AND feed_id = ?
      ) results
      ON (date = results.day)
    eos
  end

end
