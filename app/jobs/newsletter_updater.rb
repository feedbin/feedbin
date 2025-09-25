class NewsletterUpdater
  sidekiq_options queue: :utility

  TOKEN_REGEX = /
    <
    (?<token>[^@<>]+)
    @
    ((?:feedb\.in|newsletters\.feedbin\.com))
    >
  /x

  def perform(feed_id)
    entries = Entry.where(feed_id: feed_id).where("created_at > ?", Time.parse("2021-06-01"))
    entries.each do |entry|
      update(entry)
    end
  end

  def update(entry)
    return unless entry.newsletter.present?
    email = Mail.from_source(entry.newsletter)
    received = [*email.received].map(&:to_s).join
    matches = TOKEN_REGEX.match(received)

    return if !matches

    token = matches["token"]

    to = Mail::Address.new(email.to.first)
    to_local = to.local
    to_address = to.address

    # entry.update(newsletter_to: to_address, newsletter_token: token)
  rescue => exception
    Sidekiq.logger.info "Found chapters entry=#{@entry.id}"
  end

  def build
    enqueue_all(Feed, self.class)
  end
end



