class DevicePushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :default_critical

  MAX_PAYLOAD_SIZE = 4096

  apnotic_options = {
    auth_method: :token,
    cert_path: ENV["APPLE_AUTH_KEY"],
    team_id: ENV["APPLE_TEAM_ID"],
    key_id: ENV["APPLE_KEY_ID"]
  }
  # Production serves App Store and TestFlight builds; a development
  # server serves Xcode builds, whose tokens belong to APNs's sandbox.
  APNOTIC_POOL = Apnotic::ConnectionPool.public_send(Rails.env.production? ? :new : :development, apnotic_options, size: 5) { |connection|
    connection.on(:error) { |exception| ErrorService.notify(exception) }
  }

  # Reasons that mean the token will never work for its app.
  GONE = %w[BadDeviceToken DeviceTokenNotForTopic].freeze

  def perform(user_ids, entry_id, skip_read)
    ErrorService.context(user_ids: user_ids, entry_id: entry_id)

    devices = Device.v3_ios.where(user_id: User.where(id: user_ids, suspended: false).select(:id))
    return unless devices.exists?

    entry = Entry.find(entry_id)

    if skip_read
      user_ids = UnreadEntry.where(entry: entry, user_id: user_ids).pluck(:user_id)
    end

    tokens = devices.where(user_id: user_ids).pluck(:user_id, :token, :operating_system, :application)
    return if tokens.empty?
    feed = entry.feed

    feed_titles = subscription_titles(user_ids, feed)
    default_title = format_text(feed.title)

    notifications = {}
    tokens.each do |user_id, token, operating_system, application|
      # Per iteration. Reassigning feed_title carried one subscriber's private
      # rename into every later recipient's notification.
      feed_title = feed_titles[user_id] || default_title
      notification = build_notification(token, feed_title, entry, operating_system, application)
      notifications[notification.apns_id] = notification
    end

    deliver(notifications)
  end

  private

  def deliver(notifications)
    refused = Hash.new(0)
    APNOTIC_POOL.with do |connection|
      notifications.each do |_, notification|
        push = connection.prepare_push(notification)
        push.on(:response) do |response|
          Librato.increment("apns.ios.sent", source: response.status)
          reason = response.body["reason"] if %w[400 403].include?(response.status)
          if response.status == "410" || GONE.include?(reason)
            Device.where("lower(token) = ?", notification.token.downcase).take&.destroy
          end
          refused[[reason, notification.topic]] += 1 if reason && reason != "BadDeviceToken"
        end
        connection.push_async(push)
      end
      connection.join
    end
    self.class.report_refusals(refused)
  end

  # Reasons that are our setup or the app's registration, not a device
  # gone away (TopicDisallowed, DeviceTokenNotForTopic, InvalidProviderToken),
  # once per reason and topic rather than once per device.
  def self.report_refusals(refused, job: name)
    refused.each do |(reason, topic), count|
      ErrorService.notify(error_class: "#{job}##{reason}", error_message: "APNs refused #{count} pushes: #{reason}", parameters: {topic: topic, count: count})
    end
  end

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

  # application is the app's bundle id, the APNs topic it registered under.
  def build_notification(device_token, feed_title, entry, operating_system, application)
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
        body: body
      }
      notification.custom_payload = {
        feedbin: {
          entry_id: entry.id,
          title: title,
          feed: feed_title,
          author: author,
          published: published,
          content: nil
        }
      }
      if url = image_url(entry)
        notification.custom_payload[:image_url] = url
      end
      notification.category = "singleArticle"
      notification.content_available = 1
      notification.sound = "default"
      notification.priority = 10
      notification.topic = application
      notification.apns_id = SecureRandom.uuid
      notification.mutable_content = 1
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
