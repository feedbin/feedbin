class SafariPushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  VERIFIER = ActiveSupport::MessageVerifier.new(Rails.application.secrets.secret_key_base)

  APNOTIC_POOL = Apnotic::ConnectionPool.new({cert_path: ENV["APPLE_PUSH_CERT"]}, size: 5) { |connection|
    connection.on(:error) { |exception| Honeybadger.notify(exception) }
  }

  def perform(user_ids, entry_id)
    tokens = Device.where(user_id: user_ids).safari.pluck(:user_id, :token)
    entry = Entry.find(entry_id)
    feed = entry.feed

    body = entry.title || entry.summary
    body = format_text(body, 90)
    titles = subscription_titles(user_ids, feed)
    title = format_text(feed.title, 36)

    notifications = tokens.each_with_object({}) { |(user_id, token), hash|
      title = titles[user_id] || title
      notification = build_notification(token, title, body, entry_id, user_id)
      hash[notification.apns_id] = notification
    }

    APNOTIC_POOL.with do |connection|
      notifications.each do |_, notification|
        push = connection.prepare_push(notification)
        push.on(:response) do |response|
          Librato.increment("apns.safari.sent", source: response.status)
          if response.status == "410" || (response.status == "400" && response.body["reason"] == "BadDeviceToken")
            apns_id = response.headers["apns-id"]
            token = notifications[apns_id].token
            Device.where("lower(token) = ?", token.downcase).take&.destroy
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
      string = CGI.unescapeHTML(string)
      string = ApplicationController.helpers.sanitize(string, tags: []).squish.mb_chars
      omission = if string.length > max_bytes
        "..."
      else
        ""
      end
      string = string.limit(max_bytes).to_s
      string + omission
    end
    string
  end

  def build_notification(device_token, title, body, entry_id, user_id)
    Apnotic::Notification.new(device_token).tap do |notification|
      notification.alert = {
        title: title,
        body: body,
      }
      notification.url_args = [entry_id.to_s, CGI.escape(VERIFIER.generate(user_id))]
      notification.apns_id = SecureRandom.uuid
    end
  end
end
