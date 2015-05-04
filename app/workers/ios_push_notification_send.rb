class IosPushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform(user_ids, entry_id)
    users = User.where(id: user_ids)
    entry = Entry.find(entry_id)
    feed = Feed.find(entry.feed_id)

    decoder = HTMLEntities.new
    title = ActionController::Base.helpers.strip_tags(entry.feed.title)
    body = ActionController::Base.helpers.strip_tags(entry.title)

    titles = Subscription.where(feed: feed, user_id: user_ids).pluck(:user_id, :title)
    titles = titles.each_with_object({}) do |(user_id, feed_title), hash|
      hash[user_id] = feed_title
    end

    notification = {
      device_token: nil,
      category: "singleArticle",
      content_available: true,
      alert: {
        title: nil,
        body: decoder.decode(body)
      },
      custom: {
        feedbin: {
          entry_id: entry.id
        }
      }
    }

    notifications = users.each_with_object([]) do |user, array|
      title = titles[user.id] || feed.title
      tokens = user.devices.pluck(:token)
      tokens.each do |token|
        notification[:device_token] = token
        notification[:alert][:title] = title
        notification = Grocer::Notification.new(notification)
        array.push(notification)
      end
    end

    $grocer_ios.with do |pusher|
      notifications.each { |notification| pusher.push(notification) }
    end
    Librato.increment 'ios_push_notifications_sent', by: notifications.length

  end

end
