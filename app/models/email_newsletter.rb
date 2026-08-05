class EmailNewsletter

  attr_reader :full_token

  def initialize(email, full_token)
    @email = email
    @full_token = full_token
  end

  def self.token(full_token)
    full_token.sub("subscribe+", "").split("+").first
  end

  # A newsletter is keyed on its sender: the domain becomes site_url and
  # feed_url, and from_email becomes half of feed_id. Without one there is no
  # feed to file the message under, so declining is the only honest answer --
  # letting the nil through builds a feed whose site_url is the string "http:".
  def valid?
    domain.present?
  end

  def token
    self.class.token(full_token)
  end

  # Every one of these ends up in a column, so they take the same coercion the
  # body does. A header is external input like any other: the subject, the
  # display name and the raw source all carry whatever the sender put there.
  def from_email
    to_utf8(parsed_from&.address)
  end

  def to_email
    to_utf8(parsed_to&.address)
  end

  def from_name
    to_utf8(parsed_from&.name) || from_email
  end

  def name
    to_utf8(parsed_from&.name)
  end

  def from
    to_utf8(parsed_from&.decoded)
  end

  def subject
    to_utf8(@email.subject)
  end

  def text
    to_utf8(@email.text_part&.decoded || (!html? && decoded_body) || nil)
  end

  def html
    to_utf8(@email.html_part&.decoded || (html? && decoded_body) || nil)
  end

  def content
    html || text
  end

  def timestamp
    @email.date.to_i
  end

  def feed_id
    @feed_id ||= Digest::SHA1.hexdigest("#{full_token}#{from_email}")
  end

  def entry_id
    @entry_id ||= Digest::SHA1.hexdigest("#{feed_id}#{subject}#{content}")
  end

  def domain
    parsed_from&.domain
  end

  def feed_url
    "#{site_url}?#{feed_id}"
  end

  def site_url
    @site_url ||= URI::HTTP.build(host: domain).to_s
  end

  def format
    html ? "html" : "text"
  end

  def headers
    {
      "List-Unsubscribe" => @email["List-Unsubscribe"]&.decoded
    }
  end

  def to_s
    to_utf8(@email.to_s)
  end

  private

  # The decoded email body can be a string that is not valid UTF-8 — either
  # tagged ASCII-8BIT with raw high bytes (no usable charset) or tagged UTF-8
  # but containing invalid byte sequences (a body that lies about its charset).
  # Postgres rejects both on INSERT, so coerce the body to valid UTF-8.
  #
  # NUL is a separate problem wearing the same clothes. U+0000 is a legal
  # one-byte code point, so valid_encoding? is true and scrub leaves it in
  # place, but Postgres rejects it from text and varchar as a value error
  # rather than an encoding one: the wire protocol is C strings. Remove it.
  def to_utf8(value)
    return value unless value.is_a?(String)
    value = value.dup.force_encoding(Encoding::UTF_8) unless value.encoding == Encoding::UTF_8
    value = value.scrub unless value.valid_encoding?
    value.delete("\0")
  end

  # Mail::Message#decoded raises NoMethodError on a multipart message, so only
  # fall back to the whole-message body when there is a single decodable body.
  def decoded_body
    @email.decoded unless @email.multipart?
  end

  def html?
    return true if !@email.html_part.nil?
    return true if content_type.respond_to?(:starts_with?) && content_type.starts_with?("text/html")
    return false
  end

  def content_type
    @email.content_type&.strip
  end

  # "Foo, Inc. <news@foo.com>" is a comma-separated list to an RFC 5322 parser,
  # so the first address is the display-name fragment "Foo", with no domain at
  # all — and site_url, feed_url and feed_id are all derived from it. Take the
  # first address that actually names a host.
  # Three separate nils live on this path and all of them arrive by ordinary
  # mail: no From header at all, a header the parser cannot build an address
  # list from ("Some Newsletter", "<>"), and a list that parses to nothing
  # ("undisclosed-recipients:;"). The :to half was already guarded this way.
  def parsed_from
    addresses = @email[:from]&.element&.addresses
    return nil if addresses.blank?
    addresses.find { _1.domain.present? } || addresses.first
  end

  def parsed_to
    @email[:to]&.element&.addresses&.first
  end

end
