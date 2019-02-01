class DevicePushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  MAX_PAYLOAD_SIZE = 4096

  apnotic_options = {
    auth_method: :token,
    cert_path: ENV["APPLE_AUTH_KEY"],
    team_id: ENV["APPLE_TEAM_ID"],
    key_id: ENV["APPLE_KEY_ID"],
  }
  APNOTIC_POOL = Apnotic::ConnectionPool.new(apnotic_options, size: 5) { |connection|
    connection.on(:error) { |exception| Honeybadger.notify(exception) }
  }

  def perform(user_ids, entry_id, skip_read)
    Honeybadger.context(user_ids: user_ids, entry_id: entry_id)

    entry = Entry.find(entry_id)

    if skip_read
      user_ids = UnreadEntry.where(entry: entry, user_id: user_ids).pluck(:user_id)
    end

    tokens = Device.where(user_id: user_ids).ios.pluck(:user_id, :token, :operating_system)
    feed = entry.feed

    feed_titles = subscription_titles(user_ids, feed)
    feed_title = format_text(feed.title)

    notifications = tokens.each_with_object({}) { |(user_id, token, operating_system), hash|
      feed_title = feed_titles[user_id] || feed_title
      notification = build_notification(token, feed_title, entry, operating_system)
      hash[notification.apns_id] = notification
    }

    APNOTIC_POOL.with do |connection|
      notifications.each do |_, notification|
        push = connection.prepare_push(notification)
        push.on(:response) do |response|
          Librato.increment("apns.ios.sent", source: response.status)
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

  private

  def subscription_titles(user_ids, feed)
    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles.each_with_object({}) do |(user_id, feed_title), hash|
      title = format_text(feed_title)
      hash[user_id] = title.present? ? title : nil
    end
  end

  def format_text(text)
    text ||= ""
    decoder = HTMLEntities.new
    text = ActionController::Base.helpers.strip_tags(text)
    text = text.delete("\n")
    text = text.delete("\t")
    text = decoder.decode(text)
    text
  end

  def build_notification(device_token, feed_title, entry, operating_system)
    alert_title = feed_title
    if entry.tweet?
      alert_title = entry.title
    end

    body = format_text(entry.title)
    if body.empty? || entry.tweet?
      body = format_text(entry.summary)
    end
    author = format_text(entry.author)
    title = format_text(entry.title)
    published = entry.published.iso8601(6)
    if /^iPhone OS 9/.match?(operating_system)
      body = "#{feed_title}: #{body}"
    end
    notification = Apnotic::Notification.new(device_token).tap do |notification|
      notification.alert = {
        title: alert_title,
        body: body,
      }
      notification.custom_payload = {
        feedbin: {
          entry_id: entry.id,
          title: title,
          feed: feed_title,
          author: author,
          published: published,
          content: nil,
        },
      }
      if url = image_url(entry)
        notification.custom_payload[:image_url] = url
      end
      notification.category = "singleArticle"
      notification.content_available = true
      notification.sound = "default"
      notification.priority = "10"
      notification.topic = ENV["APPLE_PUSH_TOPIC"]
      notification.apns_id = SecureRandom.uuid
      notification.mutable_content = "1"
    end

    notification_size = notification.body.bytesize
    available = MAX_PAYLOAD_SIZE - notification_size
    content = EntriesHelper.text_format(entry.content)
    if content && content.bytesize < available
      notification.custom_payload[:feedbin][:content] = content
    end

    notification
  end

  def image_url(entry)
    entry.processed_image if entry.processed_image?
  end
end
