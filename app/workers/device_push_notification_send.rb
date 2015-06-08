class DevicePushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform(user_ids, entry_id)
    tokens = Device.where(user_id: user_ids).ios.pluck(:user_id, :token)
    entry = Entry.find(entry_id)
    feed = entry.feed

    body = entry.title || entry.summary
    body = format_text(body)
    titles = subscription_titles(user_ids, feed)
    title = format_text(feed.title)

    notifications = tokens.each_with_object([]) do |(user_id, token), array|
      title = titles[user_id] || title
      notification = build_notification(token, title, body, entry.id)
      notification = Grocer::Notification.new(notification)
      array.push(notification)
    end

    $grocer_ios.with do |pusher|
      notifications.each { |notification| pusher.push(notification) }
    end

    Librato.increment 'ios_push_notifications_sent', by: notifications.length
  end

  def subscription_titles(user_ids, feed)
    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles.each_with_object({}) do |(user_id, feed_title), hash|
      hash[user_id] = format_text(feed_title)
    end
  end

  def format_text(text)
    if text.present?
      decoder = HTMLEntities.new
      text = ActionController::Base.helpers.strip_tags(text)
      text = text.gsub("\n", "")
      text = text.gsub(/\t/, "")
      text = decoder.decode(text)
    end
    text
  end

  def build_notification(device_token, title, body, entry_id)
    {
      device_token: device_token,
      category: "singleArticle",
      content_available: true,
      sound: "",
      alert: {
        title: title,
        body: "#{title}: #{body}",
      },
      custom: {
        feedbin: {
          entry_id: entry_id,
          title: title,
          body: body,
        }
      }
    }
  end

end
