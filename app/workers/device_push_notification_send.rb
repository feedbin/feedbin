class DevicePushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform(user_ids, entry_id)
    users = User.where(id: user_ids)
    entry = Entry.find(entry_id)
    feed = Feed.find(entry.feed_id)

    decoder = HTMLEntities.new
    body = format_for_display(entry.title)

    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles = titles.each_with_object({}) do |(user_id, feed_title), hash|
      hash[user_id] = feed_title
    end

    notifications = users.each_with_object([]) do |user, array|
      title = titles[user.id] || feed.title
      title = format_for_display(title)
      device_tokens = user.devices.pluck(:token)
      device_tokens.each do |device_token|
        notification = build_notification(device_token, title, body, entry.id)
        notification = Grocer::Notification.new(notification)
        array.push(notification)
      end
    end

    $grocer_ios.with do |pusher|
      notifications.each { |notification| pusher.push(notification) }
    end
    Librato.increment 'ios_push_notifications_sent', by: notifications.length
    notifications
  end

  def format_for_display(text)
    decoder = HTMLEntities.new
    text = ActionController::Base.helpers.strip_tags(text)
    text = text.gsub("\n", "")
    text = text.gsub(/\t/, "")
    decoder.decode(text)
  end

  def build_notification(device_token, title, body, entry_id)
    {
      device_token: device_token,
      category: "singleArticle",
      content_available: true,
      sound: "",
      alert: {
        title: title,
        body: body
      },
      custom: {
        feedbin: {
          entry_id: entry_id
        }
      }
    }
  end

end
