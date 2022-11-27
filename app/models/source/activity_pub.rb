class Source::ActivityPub < Source

  class MissingActivityURL < StandardError; end
  class MissingOutboxURL < StandardError; end
  class MissingPageOneURL < StandardError; end
  class MissingActivity < StandardError; end

  CONTENT_TYPE = "application/activity+json"
  FINGER_TEMPLATE = "https://%{host}/.well-known/webfinger/?resource=acct:%{username}"

  def initialize(url)
    @url = url
    @feeds = []
  end

  def find
    return @feeds unless valid_username?
    feed
  end

  private

  def feed
    activity_url = find_activity_url
    outbox_url   = find_outbox_url(activity_url)
    page_one_url = find_page_one_url(outbox_url)
    activities   = find_activities(page_one_url)
    OpenStruct.new({url: page_one_url, data: activities})
  rescue => exception
    Rails.logger.error "Error finding activity: #{exception.inspect}"
    Rails.logger.error exception.backtrace.join("\n")
  end

  def find_activities(url)
    activities = HTTP.headers(accept: CONTENT_TYPE).get(url).parse
    raise MissingActivity unless activities.dig("orderedItems").length > 0
    activities
  end

  def find_page_one_url(outbox_url)
    outbox = HTTP.headers(accept: CONTENT_TYPE).get(outbox_url).parse
    url = outbox.dig("first")
    raise MissingPageOneURL if url.nil?
    url
  end

  def find_outbox_url(activity_url)
    profile = HTTP.headers(accept: CONTENT_TYPE).get(activity_url).parse
    url = profile.dig("outbox")
    raise MissingOutboxURL if url.nil?
    url
  end

  def find_activity_url
    parts = username_parts(@url)
    finger_url = FINGER_TEMPLATE % {host: parts.last, username: parts.join("@")}
    response = HTTP.get(finger_url).parse
    result = response.dig("links")&.find { _1["rel"] == "self" && _1["type"] == CONTENT_TYPE && _1["href"]}
    url = result["href"]
    raise MissingActivityURL if url.nil?
    url
  end

  def valid_username?
    parts = username_parts(@url)
    parts.length == 2 && parts.last.include?(".")
  end

  def username_parts(username)
    username.split("@").filter_map { _1 unless _1.empty? }
  end

end
