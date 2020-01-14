class NewsletterEntry

  attr_reader :newsletter, :user

  def initialize(newsletter, user = nil)
    @newsletter = newsletter
    @user = user
  end

  def self.create(newsletter, user)
    new(newsletter, user).create
  end

  def create
    create_feed
    if active? && user
      subscribe
      tag
    end
    create_entry
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

  def active?
    @active ||= begin
      result = Feed.find_by_feed_url(newsletter.feed_url)
      !result || result.subscriptions_count > 0
    end
  end

  def create_feed
    active?
    feed
    sender
  end

  def sender
    @sender ||= begin
      attributes = {
        token: newsletter.token,
        full_token: newsletter.full_token,
        email: newsletter.from_email,
        name: newsletter.name,
        active: active?
      }
      NewsletterSender.create_with(attributes).find_or_create_by(feed: feed).tap do |record|
        record.update(attributes)
      end
    end
  end

  def feed
    @feed ||= begin
      attributes = {
        title: newsletter.from_name,
        feed_url: newsletter.feed_url,
        site_url: newsletter.site_url,
        feed_type: :newsletter,
      }
      Feed.create_with(attributes).find_or_create_by(feed_url: newsletter.feed_url).tap do |record|
        record.update(attributes)
      end
    end
  end

  def create_entry
    @create_entry ||= begin
      attributes = {
        author: newsletter.from_name,
        content: newsletter.content,
        title: newsletter.subject,
        url: Rails.application.routes.url_helpers.newsletter_entry_url(newsletter.entry_id, host: ENV["PUSH_URL"]),
        entry_id: newsletter.entry_id,
        published: Time.now,
        updated: Time.now,
        public_id: newsletter.entry_id,
        data: {newsletter_text: newsletter.text, type: "newsletter", format: newsletter.format, newsletter: newsletter},
      }
      feed.entries.create!(attributes).tap do |record|
        NewsletterSaver.perform_async(record.id)
      end
    end
  end
end
