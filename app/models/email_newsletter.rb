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
    @email.text_part&.decoded || !html? && @email.decoded || nil
  end

  def html
    @email.html_part&.decoded || html? && @email.decoded || nil
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
    @entry_id ||= Digest::SHA1.hexdigest("#{feed_id}#{subject}#{timestamp}")
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

  def html?
    return true if !@email.html_part.nil?
    return true if content_type.respond_to?(:starts_with?) && content_type.starts_with?("text/html")
    return false
  end

  def content_type
    @email.content_type&.strip
  end

  def parsed_from
    @email[:from].address_list.addresses.first
  end

end
