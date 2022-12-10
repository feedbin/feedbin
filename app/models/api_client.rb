class ApiClient
  class Error < StandardError
  end

  def initialize(access_token)
    @access_token = access_token
  end

  def feed_items_list(params:, limit: nil)
    paged_feed_items(
      path: "/api/v2/feed_items/list",
      params: params,
      limit: limit
    )
  end

  def subscriptions_list
    request(path: "/api/v2/subscriptions/list")
  end

  def streams_list
    request(path: "/api/v2/streams/list")
  end

  private

  def paged_feed_items(path:, params:, limit:)
    params[:offset] = 0 if params[:offset].nil?
    all = []
    loop do
      response = request(path: path, params: params)
      result = response.safe_dig("feed_items")
      break if result.count == 0
      all += result
      params[:offset] += 100
      break if !limit.nil? && params[:offset] == limit
    end
    all
  end

  def request(path:, params: {})
    url = URI::HTTPS.build({
      host: ENV["ACCOUNT_HOST"],
      path: path,
      query: default_params.merge(params).to_query
    })
    response = HTTP.follow().headers(user_agent: "Feedbin").get(url)

    raise ApiClient::Error.new(response.status.reason) unless response.status.success?

    result = response.parse
    error_message = result.safe_dig("error")
    status = result.safe_dig("result")

    if !error_message.nil? || status == "error"
      raise ApiClient::Error.new(error_message || "Unknown API error.")
    end

    result
  rescue HTTP::Error => exception
    raise ApiClient::Error.new("HTTP error: #{exception.message}")
  end

  def default_params
    { access_token: @access_token }
  end
end