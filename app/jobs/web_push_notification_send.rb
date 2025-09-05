class WebPushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :default_critical

  VERIFIER = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)

  apnotic_options = {
    auth_method: :token,
    cert_path: ENV["APPLE_AUTH_KEY"],
    team_id: ENV["APPLE_TEAM_ID"],
    key_id: ENV["APPLE_KEY_ID"]
  }
  APNOTIC_POOL = Apnotic::ConnectionPool.new(apnotic_options, size: 5) { |connection|
    connection.on(:error) { |exception|
      Sidekiq.logger.info "ConnectionError exception=#{exception.message}"
      ErrorService.notify(
        error_class: "WebPushNotificationSend#ConnectionError",
        error_message: exception.message,
        parameters: {exception: exception}
      )
    }
  }

  def perform(user_ids, entry_id, skip_read)
    devices = Device.where(user_id: user_ids, device_type: [:safari, :browser])
    entry = Entry.find(entry_id)
    feed = entry.feed

    if skip_read
      user_ids = UnreadEntry.where(entry: entry, user_id: user_ids).pluck(:user_id)
    end

    if entry.tweet?
      body = entry.tweet.main_tweet.full_text
      title = format_text(entry.tweet.main_tweet.user.name, 36)
      titles = {}
    else
      body = entry.title || entry.summary
      title = format_text(feed.title, 36)
      titles = subscription_titles(user_ids, feed)
    end
    body = format_text(body, 90)

    safari_notifications = {}
    devices.each do |device|
      if user_title = titles[device.user_id]
        title = format_text(user_title, 36)
      end

      if device.safari?
        notification = build_notification(device.token, title, body, entry_id, device.user_id)
        safari_notifications[notification.apns_id] = notification
      elsif device.browser?
        send_browser_notification(device, title, body, entry)
      end
    end

    return unless safari_notifications.present?

    APNOTIC_POOL.with do |connection|
      safari_notifications.each do |_, notification|
        push = connection.prepare_push(notification)
        push.on(:response) do |response|
          Librato.increment("apns.safari.sent", source: response.status)
          if response.status == "410" || (response.status == "400" && response.body["reason"] == "BadDeviceToken")
            apns_id = response.headers["apns-id"]
            token = safari_notifications[apns_id].token
            Device.where_lower(token: token).take&.destroy
          end
        end
        connection.push_async(push)
      end
      connection.join
    end

  end

  def subscription_titles(user_ids, feed)
    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles.each_with_object({}) do |(user_id, feed_title), hash|
      hash[user_id] = format_text(feed_title, 36)
    end
  end

  def format_text(string, max_bytes)
    if string.present?
      string = ApplicationController.helpers.sanitize(string, tags: []).squish.mb_chars
      omission = if string.length > max_bytes
        "…"
      else
        ""
      end
      string = string.limit(max_bytes).to_s
      string = string.strip + omission
      string = CGI.unescapeHTML(string)
    end
    string
  end

  def view_url(entry_id, user_id)
    Rails.application.routes.url_helpers.push_view_entry_url(entry_id,
      user: CGI.escape(VERIFIER.generate(user_id)),
      host: ENV["PUSH_URL"]
    )
  end

  def send_browser_notification(device, title, body, entry)
    message = {
      title: body,
      payload: {
        body: title,
        data: {
          defaultAction: view_url(entry.id, device.user_id)
        }
      }
    }

    if entry.processed_image?
      message[:payload][:icon] = entry.processed_image
    end

    WebPush.payload_send(
      endpoint: device.data["endpoint"],
      message: JSON.generate(message),
      p256dh: device.data["keys"]["p256dh"],
      auth: device.data["keys"]["auth"],
      urgency: "high",
      ttl: 1.hour.to_i,
      vapid: {
        subject: "mailto:#{ENV["FROM_ADDRESS"]}",
        pem: Feedbin::Application.config.vapid_key.to_pem
      }
    )

  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized => exception
    device.destroy
    ErrorService.notify(
      error_class: exception.to_s,
      error_message: exception.message,
      context: {
        response: exception.response,
        host: exception.host,
        user: device.user_id
      }
    )
  rescue => exception
    ErrorService.notify(exception)
    raise unless Rails.env.production?
  end

  def build_notification(device_token, title, body, entry_id, user_id)
    Apnotic::Notification.new(device_token).tap do |notification|
      notification.alert = {
        title: title,
        body: body
      }
      notification.url_args = [entry_id.to_s, CGI.escape(VERIFIER.generate(user_id))]
      notification.apns_id = SecureRandom.uuid
    end
  end
end