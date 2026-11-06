class PodcastPushNotification
  include Sidekiq::Worker

  FIREBASE = FirebaseMessaging.new

  def perform(user_id, entry_id)
    ErrorService.context(user_id: user_id, entry_id: entry_id)
    entry = Entry.find(entry_id)
    devices = Device.where(user_id: user_id, active: true)
    devices.podcast.pluck(:token).each { |token| push_apns(token, entry, user_id) }
    return unless FIREBASE.configured?
    devices.podcast_android.pluck(:token).each { |token| push_firebase(token, entry, user_id) }
  end

  private

  def push_apns(token, entry, user_id)
    notification = build_notification(token, entry)

    response = DevicePushNotificationSend::APNOTIC_POOL.with do |connection|
      connection.push(notification)
    end

    if response.status == "410" || (response.status == "400" && response.body["reason"] == "BadDeviceToken")
      Sidekiq.logger.info "Bad device token user_id=#{user_id}"
      remove_device(token)
    end
  end

  # Rescued so one failure doesn't stop the other devices; a job retry would push to them twice.
  def push_firebase(token, entry, user_id)
    response = FIREBASE.deliver(firebase_message(token, entry))
    if response.unregistered?
      Sidekiq.logger.info "Unregistered Firebase token user_id=#{user_id}"
      remove_device(token)
    elsif !response.success?
      Sidekiq.logger.info "Firebase push failed status=#{response.status} error=#{response.error_code} user_id=#{user_id}"
    end
  rescue => exception
    ErrorService.notify(exception)
  end

  def remove_device(token)
    Device.where("lower(token) = ?", token.downcase).take&.destroy
  end

  # A data message, so the app builds the notification. FCM requires string values.
  def firebase_message(token, entry)
    content = notification_content(entry)
    {
      token: token,
      data: {
        feed_id:   entry.feed_id.to_s,
        entry_id:  entry.id.to_s,
        title:     content[:title],
        subtitle:  content[:subtitle],
        body:      content[:body],
        image_url: content[:image].to_s
      },
      android: {priority: "high"}
    }
  end

  def notification_content(entry)
    {
      title:    format_text(entry.title),
      subtitle: format_text(entry.feed.title),
      body:     format_text(find_summary(entry) || entry.summary),
      image:    entry.data["itunes_image"] || entry.feed.options["itunes_image"]
    }
  end

  def format_text(text)
    text ||= ""
    decoder = HTMLEntities.new
    text = ActionController::Base.helpers.strip_tags(text)
    text = text.delete("\n")
    text = text.delete("\t")
    text = text.strip
    text = decoder.decode(text)
    text
  end

  def find_summary(entry)
    options = [entry.data.safe_dig("itunes_subtitle"), entry.data.safe_dig("itunes_summary")]
    options = options.compact
    return options.first if options.count == 1
    options.min_by(&:length)
  end

  def build_notification(token, entry)
    content = notification_content(entry)

    Apnotic::Notification.new(token).tap do |notification|
      notification.alert = content.slice(:title, :subtitle, :body)
      notification.custom_payload = {
        data: {
          feed_id:   entry.feed_id,
          entry_id:  entry.id,
          image_url: content[:image]
        }
      }

      notification.apns_id           = SecureRandom.uuid
      notification.topic             = ENV["APPLE_PUSH_TOPIC_PODCAST"]
      notification.category          = "viewCategory"
      notification.thread_id         = entry.feed_id
      notification.content_available = 1
      notification.mutable_content   = 1
    end
  end
end
