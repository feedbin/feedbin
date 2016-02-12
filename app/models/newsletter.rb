class Newsletter

  def initialize(event)
    @event = event
  end

  def valid?
    @event["event"] == "inbound"
  end

  def token
    @token ||= begin
      to_email.sub("@newsletters.feedbin.com", "").sub("test-subscribe+", "").sub("subscribe+", "")
    end
  end

  def to_email
    @event["msg"]["email"]
  end

  def from_email
    @event["msg"]["from_email"]
  end

  def from_name
    @event["msg"]["from_name"] || from_email
  end

  def subject
    @event["msg"]["subject"]
  end

  def text
    @event["msg"]["text"]
  end

  def html
    @event["msg"]["html"]
  end

  def content
    html || text
  end

  def timestamp
    @event["ts"]
  end

  def feed_id
    @feed_id ||= Digest::SHA1.hexdigest("#{token}#{from_email}")
  end

  def entry_id
    @entry_id ||= Digest::SHA1.hexdigest("#{feed_id}#{subject}#{timestamp}")
  end

  def domain
    @domain ||= Mail::Address.new(from_email).domain
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

end