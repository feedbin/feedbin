class Newsletter

  def initialize(event)
    @event = event
  end

  def valid?
    @event["event"] == "inbound"
  end

  def token
    @token ||= begin
      to_email.sub("@newsletters.feedbin.com", "").sub("test-subscribe-", "").sub("subscribe-", "")
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
end