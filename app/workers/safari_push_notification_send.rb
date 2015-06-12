# ENV['RAILS_ENV'] = 'production'; reload!; p = SafariPushNotificationSend.new; p.perform([2], 2)
class SafariPushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform(user_ids, entry_id)
    users = User.where(id: user_ids)
    tokens = Device.where(user_id: user_ids).safari.pluck(:user_id, :token)
    entry = Entry.find(entry_id)
    feed = entry.feed
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)

    body = entry.title || entry.summary
    body = format_text(body, 90)
    titles = subscription_titles(user_ids, feed)
    title = format_text(feed.title, 36)

    notifications = tokens.each_with_object([]) do |(user_id, token), array|
      title = titles[user_id] || title
      notification = build_notification(token, title, body, entry_id, user_id, verifier)
      notification = Grocer::SafariNotification.new(notification)
      array.push(notification)
    end

    $grocer.with do |pusher|
      notifications.each { |notification| pusher.push(notification) }
    end

    Librato.increment 'push_notifications_sent', by: notifications.length
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
      if string.length > max_bytes
        omission = '...'
      else
        omission = ''
      end
      string = string.limit(max_bytes).to_s
      string + omission
    end
    string
  end

  def build_notification(device_token, title, body, entry_id, user_id, verifier)
    {
      device_token: device_token,
      title: title,
      body: body,
      url_args: [entry_id.to_s, CGI::escape(verifier.generate(user_id))]
    }
  end

end
