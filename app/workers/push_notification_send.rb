class PushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  # ENV['RAILS_ENV'] = 'production'; reload!; p = PushNotificationSend.new; p.perform(1, [1])
  #
  # Payload must be less than 256 bytes a payload without the body is about
  # 157 bytes
  def perform(entry_id, user_ids)
    if $grocer
      notifications = build_notifications(entry_id, user_ids)
      send_notifications(notifications)
    end
  end

  def send_notifications(notifications)
    $grocer.with do |pusher|
      notifications.each { |notification| pusher.push(notification) }
    end
    Librato.increment 'push_notifications_sent', by: notifications.length
  end

  def build_notifications(entry_id, user_ids)
    entry = Entry.find(entry_id)
    feed = Feed.find(entry.feed_id)
    users = User.where(id: user_ids)
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)

    # Use user specified feed titles where available
    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles = titles.each_with_object({}) do |(user_id, feed_title), hash|
      hash[user_id] = feed_title
    end

    notifications = []
    users.each do |user|
      unless user.apple_push_notification_device_token.blank?
        title = titles[user.id] || feed.title
        notifications << Grocer::SafariNotification.new(
          device_token: user.apple_push_notification_device_token,
          title: format_string(title, 36),
          body: format_string(entry.title, 90),
          url_args: [entry.id.to_s, CGI::escape(verifier.generate(user.id))]
        )
      end
    end
    notifications
  end

  def format_string(string, max_bytes)
    string = CGI.unescapeHTML(string)
    string = ApplicationController.helpers.sanitize(string, tags: []).squish.mb_chars
    if string.length > max_bytes
      omission = '...'
    else
      omission = ''
    end
    string = string.limit(max_bytes).to_s
    string + omission
  end
end
