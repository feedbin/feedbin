class PodcastPushNotification
  include Sidekiq::Worker

  def perform(user_id, entry_id)
    ErrorService.context(user_id: user_id, entry_id: entry_id)
    entry = Entry.find(entry_id)
    tokens = Device.where(user_id: user_id, active: true).podcast.pluck(:token)
    tokens.each do |token|
      notification = build_notification(token, entry)

      response = DevicePushNotificationSend::APNOTIC_POOL.with do |connection|
        connection.push(notification)
      end

      if response.status == "410" || (response.status == "400" && response.body["reason"] == "BadDeviceToken")
        Rails.logger.info { "Bad device token user_id=#{user_id}" }
        Device.where("lower(token) = ?", token.downcase).take&.destroy
      end
    end
  end

  private

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
    title    = format_text(entry.title)
    subtitle = format_text(entry.feed.title)
    body     = find_summary(entry) || entry.summary
    body     = format_text(body)
    image    = entry.data["itunes_image"] || entry.feed.options["itunes_image"]

    Apnotic::Notification.new(token).tap do |notification|
      notification.alert = {
        title:    title,
        subtitle: subtitle,
        body:     body
      }
      notification.custom_payload = {
        data: {
          feed_id:   entry.feed_id,
          entry_id:  entry.id,
          image_url: image
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
