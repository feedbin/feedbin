class NewsletterEntry

  attr_reader :newsletter, :user

  def initialize(newsletter, user)
    @newsletter = newsletter
    @user = user
  end

  def create
    if active?
      subscribe
      tag
    end
    create_entry
    upload
  end

  def subscribe
    user.subscriptions.find_or_create_by(feed: feed)
  end

  def tag
    if user.newsletter_tag.present? && !already_tagged?
      feed.tag(user.newsletter_tag, user)
    end
  end

  def already_tagged?
    user.taggings.where(feed: feed).exists?
  end

  def upload
    NewsletterSaver.perform_async(entry.id)
  end

  def active?
    @active ||= begin
      result = Feed.find_by_feed_url(feed_url: newsletter.feed_url)
      !result || result.subscriptions_count > 0
    end
  end

  def sender
    @sender ||= begin
      options = {
        token: newsletter.token,
        full_token: newsletter.full_token,
        email: newsletter.email,
        name: newsletter.name,
        active: active?
      }
      NewsletterSender.create_with(options).find_or_create_by(feed: feed)
    end
  end

  def feed
    @feed ||= begin
      options = {
        title: newsletter.from_name,
        feed_url: newsletter.feed_url,
        site_url: newsletter.site_url,
        feed_type: :newsletter,
      }
      Feed.create_with(options).find_or_create_by(feed_url: newsletter.feed_url)
    end
  end

  def create_entry
    @entry ||= begin
      feed.entries.create!({
        author: newsletter.from_name,
        content: newsletter.content,
        title: newsletter.subject,
        url: newsletter_entry_url(newsletter.entry_id),
        entry_id: newsletter.entry_id,
        published: Time.now,
        updated: Time.now,
        public_id: newsletter.entry_id,
        data: {newsletter_text: newsletter.text, type: "newsletter", format: newsletter.format, newsletter: newsletter},
      })
    end
  end
end
