class DevicePushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  APNOTIC_POOL = Apnotic::ConnectionPool.new({cert_path: ENV['APPLE_PUSH_CERT_IOS']}, size: 5)

  def perform(user_ids, entry_id)
    Honeybadger.context(user_ids: user_ids, entry_id: entry_id)
    tokens = Device.where(user_id: user_ids).ios.pluck(:user_id, :token)
    entry = Entry.find(entry_id)
    feed = entry.feed

    feed_titles = subscription_titles(user_ids, feed)
    feed_title = format_text(feed.title)

    notifications = tokens.each_with_object([]) do |(user_id, token), array|
      feed_title = feed_titles[user_id] || feed_title
      notification = build_notification(token, feed_title, entry)
      array.push(notification)
    end

    notifications.each do |notification|
      APNOTIC_POOL.with do |connection|
        response = connection.push(notification)
        if response.status == '410' || (response.status == '400' && response.body['reason'] == 'BadDeviceToken')
          Device.where("lower(token) = ?", notification.token.downcase).take&.destroy
        end
        Librato.increment('apns.safari.sent', source: response.status)
      end
    end
  end

  private

  def subscription_titles(user_ids, feed)
    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles.each_with_object({}) do |(user_id, feed_title), hash|
      title = format_text(feed_title)
      hash[user_id] = (title.present?) ? title : nil
    end
  end

  def format_text(text)
    text ||= ""
    decoder = HTMLEntities.new
    text = ActionController::Base.helpers.strip_tags(text)
    text = text.gsub("\n", "")
    text = text.gsub(/\t/, "")
    text = decoder.decode(text)
    text
  end

  def build_notification(device_token, feed_title, entry)
    body = format_text(entry.title || entry.summary)
    author = format_text(entry.author)
    title = format_text(entry.title)
    published = entry.published.iso8601(6)
    Apnotic::Notification.new(device_token).tap do |notification|
      notification.alert = {
        title: feed_title,
        body: "#{feed_title}: #{body}",
      }
      notification.custom_payload = {
        feedbin: {
          entry_id: entry.id,
          title: title,
          feed: feed_title,
          author: author,
          published: published
        }
      }
      notification.category = "singleArticle"
      notification.content_available = true
      notification.sound = ""
      notification.priority = "10"
      notification.topic = ENV['APPLE_PUSH_TOPIC']
    end
  end

end
