require 'apn_connection'

class DevicePushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  APN_POOL = ConnectionPool.new(size: 2, timeout: 300) do
    APNConnection.new
  end

  def perform(user_ids, entry_id)
    Honeybadger.context(user_ids: user_ids, entry_id: entry_id)
    tokens = Device.where(user_id: user_ids).ios.pluck(:user_id, :token)
    entry = Entry.find(entry_id)
    feed = entry.feed

    feed_titles = subscription_titles(user_ids, feed)
    feed_title = format_text(feed.title) || ""

    notifications = tokens.each_with_object([]) do |(user_id, token), array|
      feed_title = feed_titles[user_id] || feed_title
      notification = build_notification(token, feed_title, entry)
      array.push(notification)
    end

    APN_POOL.with do |connection|
      notifications.each do |notification|
        connection.write(notification.message)
      end
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

  def build_notification(device_token, feed_title, entry)
    body = format_text(entry.title || entry.summary || "")
    author = format_text(entry.author || "")
    title = format_text(entry.title || "")
    published = entry.published.iso8601(6)

    notification = Houston::Notification.new(device: device_token)
    notification.category = "singleArticle"
    notification.content_available = true
    notification.sound = ""
    notification.alert = {
      title: feed_title,
      body: "#{feed_title}: #{body}",
    }
    notification.custom_data = {
      feedbin: {
        entry_id: entry.id,
        title: title,
        feed: feed_title,
        author: author,
        published: published
      }
    }
    notification
  end

end
