module ActivityPub
  class AutoDiscovery
    class MissingActivityURL < StandardError; end
    class MissingOutboxURL < StandardError; end
    class MissingPageOneURL < StandardError; end
    class MissingActivity < StandardError; end

    CONTENT_TYPE = "application/activity+json"
    DISCOVERY_TEMPLATE = "https://%{host}/.well-known/webfinger/?resource=acct:%{username}"

    def self.find(username)
      new(username).feed
    end

    def feed
      activity_url = find_activity_url
      actor        = find_actor(activity_url)
      page_one_url = find_page_one_url(actor.dig("outbox"))
      activities   = find_activities(page_one_url)
      OpenStruct.new({url: page_one_url, data: activities, actor_url: activity_url})
    rescue => exception
      Rails.logger.error "Error finding activity: #{exception.inspect}"
      Rails.logger.error exception.backtrace.join("\n")
    end

    private

    def initialize(username)
      @username = username
    end

    def find_activities(url)
      response = HTTP.headers(accept: CONTENT_TYPE).get(url).parse
      raise MissingActivity unless response.dig("orderedItems").length > 0
      response
    end

    def find_page_one_url(outbox_url)
      response = HTTP.headers(accept: CONTENT_TYPE).get(outbox_url).parse
      url = response.dig("first")
      raise MissingPageOneURL if url.nil?
      url
    end

    def find_actor(activity_url)
      response = HTTP.headers(accept: CONTENT_TYPE).get(activity_url).parse
      url = response.dig("outbox")
      raise MissingOutboxURL if url.nil?
      response
    end

    def find_activity_url
      parts = username_parts(@username)
      discovery_url = DISCOVERY_TEMPLATE % {host: parts.last, username: parts.join("@")}
      response = HTTP.get(discovery_url).parse
      result = response.dig("links")&.find { _1["rel"] == "self" && _1["type"] == CONTENT_TYPE && _1["href"]}
      url = result["href"]
      raise MissingActivityURL if url.nil?
      url
    end

    def valid_username?
      parts = username_parts(@username)
      parts.length == 2 && parts.last.include?(".")
    end

    def username_parts(username)
      username.split("@").filter_map { _1 unless _1.empty? }
    end
  end
end