class Newsletter2

  def initialize(params)
    @params = params
  end

  def valid?
    @params["X-Mailgun-Incoming"] == "Yes" && signature_valid?
  end

  def token
    @token ||= begin
      to_email.sub("@newsletters.feedbin.com", "").sub("@development.newsletters.feedbin.com", "").sub("test-subscribe+", "").sub("subscribe+", "")
    end
  end

  def to_email
    @params["recipient"]
  end

  def from_email
    parsed_from.address
  end

  def from_name
    parsed_from.name || from_email
  end

  def subject
    @params["subject"]
  end

  def text
    @params["body-plain"]
  end

  def html
    @params["body-html"]
  end

  def content
    html || text
  end

  def timestamp
    @params["timestamp"]
  end

  def feed_id
    @feed_id ||= Digest::SHA1.hexdigest("#{token}#{from_email}")
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

  private

  def parsed_from
    Mail::Address.new(@params["from"])
  rescue Mail::Field::ParseError
    name, address = @params["from"].split(/[<>]/).map(&:strip)
    domain = address.split("@").last
    OpenStruct.new(name: name, address: address, domain: domain)
  end

  def signature_valid?
    digest = OpenSSL::Digest::SHA256.new
    data = [@params["timestamp"], @params["token"]].join
    @params["signature"] == OpenSSL::HMAC.hexdigest(digest, ENV['MAILGUN_INBOUND_KEY'], data)
  end

end