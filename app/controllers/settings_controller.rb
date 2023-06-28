class SettingsController < ApplicationController

  def index
    render Settings::IndexView.new(user: current_user), layout: "settings"
  end

  def account
    @user = current_user
    @last_payment = @user.billing_events
      .order(created_at: :desc)
      .where(event_type: "charge.succeeded")
      .where("created_at >= :expiration_cutoff", {expiration_cutoff: 3.days.ago})
      .take
  end

  def appearance
    @user = current_user
  end

  def settings_update
    @user = current_user
    @user.attributes = user_settings_params
    if @user.save
      respond_to do |format|
        flash[:notice] = "Settings updated."
        format.js { flash.discard }
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
        flash[:alert] = @user.errors.full_messages.join(". ") + "."
        format.js { flash.discard }
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

  def format
    old_settings = begin
                     JSON.parse(cookies.permanent.signed[:settings])
                   rescue
                     {}
                   end
    new_settings = user_format_params
    cookies.permanent.signed[:settings] = {
      value: JSON.generate(old_settings.merge(new_settings)),
      httponly: true,
      secure: Feedbin::Application.config.force_ssl
    }
    @user = current_user
    @user.update!(new_settings)
  end

  def sticky
    @user = current_user
    @subscription = @user.subscriptions.where(feed_id: params[:feed_id]).first
    if @subscription.present?
      @subscription.update(view_inline: !@subscription.view_inline)
    end
  end

  def subscription_view_mode
    @user = current_user
    @subscription = @user.subscriptions.where(feed_id: params[:feed_id]).first
    if @subscription.present?
      @subscription.update(subscription_view_mode_params)
    end
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
    if %w[minimized maximized].include?(params[:audio_panel_size])
      user.update(audio_panel_size: params[:audio_panel_size])
    end
    head :ok
  end

  def newsletters_pages
    render Settings::NewslettersPagesView.new(user: current_user, subscription_ids: @user.subscriptions.pluck(:feed_id)), layout: "settings"
  end

  private

  def user_settings_params
    params.require(:user).permit(:entry_sort, :starred_feed_enabled, :precache_images,
      :show_unread_count, :sticky_view_inline, :mark_as_read_confirmation,
      :apple_push_notification_device_token, :receipt_info, :entries_display,
      :entries_feed, :entries_time, :entries_body, :ui_typeface, :theme,
      :hide_recently_read, :hide_updated, :disable_image_proxy, :entries_image,
      :now_playing_entry, :hide_recently_played, :view_links_in_app, :newsletter_tag,
      :hide_airshow)
  end

  def user_now_playing_params
    params.require(:user).permit(:now_playing_entry)
  end

  def user_format_params
    params.require(:user).permit(:font_size, :theme, :font, :entry_width, :view_mode, :feeds_width, :entries_width)
  end

  def subscription_view_mode_params
    params.require(:subscription).permit(:view_mode)
  end
end
