class NewsletterReceiver
  attr_reader :newsletter, :user
  include Sidekiq::Worker
  sidekiq_options queue: :parse

  def perform(address, url)
    @address = Mail::Address.new(address)
    @url = Addressable::URI.parse(url)
    @user = original_authentication_token&.user

    Sidekiq.logger.info "Newsletter processing user_id=#{@user&.id} address=#{address} url=#{url}"

    if @user && full_authentication_token&.active?
      @newsletter = parse_newsletter
      # A newsletter with no usable sender has no feed to belong to -- see
      # EmailNewsletter#valid?. Decline it here rather than letting the nil
      # reach the sender and feed rows, where it is a NotNullViolation the job
      # will retry twenty-five times without ever succeeding.
      if !@newsletter.valid?
        Sidekiq.logger.info "Newsletter declined, no usable sender url=#{url}"
      elsif entry = create
        Sidekiq.logger.info "Newsletter created public_id=#{entry.public_id}"
      end
    else
      Sidekiq.logger.info "Newsletter skipped user_id=#{@user&.id} address=#{address} url=#{url}"
    end
    # Only reached when the message was stored or deliberately declined. An
    # unexpected failure above must leave the source in place, because it is
    # the only copy of the email and Sidekiq is going to retry.
    storage_client.delete_object(@url.host, storage_path)
  end

  private

  def create
    create_feed
    if active? && user
      subscribe
      tag
    end
    begin
      create_entry
    rescue ActiveRecord::RecordNotUnique
      # public_id is SHA1(feed_id + subject + content), so a collision means
      # this exact message is already stored — a redelivery, or the worker that
      # won the race. Nothing left to do, and the source can go.
      Sidekiq.logger.info "Newsletter already stored public_id=#{newsletter.entry_id}"
      nil
    end
  end

  def subscribe
    user.subscriptions.create_with(view_mode: :newsletter).find_or_create_by(feed: feed)
  end

  def tag
    tag = full_authentication_token.newsletter_tag || original_authentication_token.newsletter_tag
    if tag.present? && !already_tagged?
      feed.tag(tag, user)
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
        record.update(attributes.except(:feed_url))
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
        newsletter_to: newsletter.to_email,
        newsletter_token: @address.local,
        data: {newsletter_text: newsletter.text, type: "newsletter", format: newsletter.format, newsletter_to: newsletter.full_token}
      }
      feed.entries.create!(attributes).tap do |record|
        NewsletterSaver.perform_async(record.id)
      end
    # ArgumentError as well as StatementInvalid: the adapter refuses a NUL in a
    # bind parameter before the statement is ever sent, so that rejection never
    # arrives wearing an ActiveRecord class.
    rescue ActiveRecord::StatementInvalid, ArgumentError
      ErrorService.context(unstorable_attributes: unstorable_attributes(attributes))
      raise
    end
  end

  # Names the attributes Postgres will refuse, so the failing column shows up in
  # the error notice instead of just the raw byte sequence.
  def unstorable_attributes(attributes)
    attributes.flat_map do |key, value|
      if value.is_a?(Hash)
        value.filter_map { |nested_key, nested_value| "#{key}.#{nested_key}" if unstorable?(nested_value) }
      elsif unstorable?(value)
        key.to_s
      end
    end.compact
  end

  # Two separate rejections: bytes that are not valid UTF-8, and NUL, which is
  # valid UTF-8 and still cannot cross a wire protocol built on C strings. The
  # encoding test alone named nothing for the second, which is how a thousand
  # NUL rejections went undiagnosed.
  def unstorable?(value)
    return false unless value.is_a?(String)
    bytes = value.encoding == Encoding::UTF_8 ? value : value.dup.force_encoding(Encoding::UTF_8)
    !bytes.valid_encoding? || bytes.include?("\0")
  end
end
