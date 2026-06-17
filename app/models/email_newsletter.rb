class EmailNewsletter

  attr_reader :full_token

  def initialize(email, full_token)
    @email = email
    @full_token = full_token
  end

  def self.token(full_token)
    full_token.sub("subscribe+", "").split("+").first
  end

  def valid?
    true
  end

  def token
    self.class.token(full_token)
  end

  def from_email
    parsed_from.address
  end

  def to_email
    parsed_to&.address
  end

  def from_name
    parsed_from.name || from_email
  end

  def name
    parsed_from.name
  end

  def from
    parsed_from.decoded
  end

  def subject
    @email.subject
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
    parsed_from.domain
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
    @email.to_s
  end

  private

  # The decoded email body can be a string that is not valid UTF-8 — either
  # tagged ASCII-8BIT with raw high bytes (no usable charset) or tagged UTF-8
  # but containing invalid byte sequences (a body that lies about its charset).
  # Postgres rejects both on INSERT, so coerce the body to valid UTF-8.
  def to_utf8(value)
    return value unless value.is_a?(String)
    value = value.dup.force_encoding(Encoding::UTF_8) unless value.encoding == Encoding::UTF_8
    value.valid_encoding? ? value : value.scrub
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

  def parsed_from
    @email[:from].element.addresses.first
  end

  def parsed_to
    @email[:to]&.element&.addresses&.first
  end

end
