class NewsletterReceiver
  attr_reader :newsletter, :user
  include Sidekiq::Worker
  sidekiq_options queue: :parse

  def perform(address, url)
    @address = Mail::Address.new(address)
    @url = Addressable::URI.parse(url)
    @user = original_authentication_token&.user

    if @user && full_authentication_token&.active?
      @newsletter = parse_newsletter
      if entry = create
        Sidekiq.logger.info "Newsletter created public_id=#{entry.public_id}"
      end
    end
    storage_client.delete_object(@url.host, storage_path)
  end

  private

  def create
    create_feed
    if active? && user
      subscribe
      tag
    end
    create_entry
  rescue ActiveRecord::RecordNotUnique
  end

  def subscribe
    user.subscriptions.create_with(view_mode: :newsletter).find_or_create_by(feed: feed)
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

  def parse_newsletter
    email = storage_client.get_object(@url.host, storage_path)
    email = Mail.from_source(email.body)
    EmailNewsletter.new(email, @address.local)
  end

  def parsed_token
    EmailNewsletter.token(@address.local)
  end

  def storage_path
    @url.path.delete_prefix("/")
  end

  def full_authentication_token
    return @full_authentication_token if defined?(@full_authentication_token)
    @full_authentication_token = user.authentication_tokens.newsletters.find_or_create_by(token: @address.local)
  end

  def original_authentication_token
    return @original_authentication_token if defined?(@original_authentication_token)
    @original_authentication_token = AuthenticationToken.newsletters.where(token: parsed_token).take
  end

  def storage_client
    @storage_client ||= begin
      Fog::Storage.new(STORAGE)
    end
  end

  def sender
    @sender ||= begin
      attributes = {
        token: newsletter.full_token,
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
        feed_type: :newsletter
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
        newsletter: newsletter.to_s,
        newsletter_from: newsletter.from,
        data: {newsletter_text: newsletter.text, type: "newsletter", format: newsletter.format, newsletter_to: newsletter.full_token}
      }
      feed.entries.create!(attributes).tap do |record|
        NewsletterSaver.perform_async(record.id)
      end
    end
  end
end
