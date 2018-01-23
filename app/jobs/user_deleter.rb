class UserDeleter
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id)
    user = User.find(user_id)
    tags = user.feed_tags
    feeds = user.feeds.xml
    titles = user.subscriptions.pluck(:feed_id, :title).each_with_object({}) do |(feed_id, title), hash|
      hash[feed_id] = title
    end
    opml = SubscriptionsController.render(:index, assigns: {user: user, tags: tags, feeds: feeds, titles: titles}, layout: nil)
    UserMailer.account_closed(user.id, opml).deliver_now
    user.destroy
  end

end