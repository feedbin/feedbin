class TwitterFeed
  def initialize(url, token, secret)
    url = url.strip
    url = shortcut(url)
    if url.start_with?("twitter.com")
      url = "https://#{url}"
    end
    @url = URI.parse(url)
    @api = TwitterAPI.new(token, secret)
  end

  def options

  end

  def load_tweets
    if value = user
      @api.client.user_timeline(value, exclude_replies: true, count: 100, extended_tweet: true)
    elsif value = search || value = hashtag
      @api.client.search(value, count: 100, result_type: "recent", include_entities: true, extended_tweet: true).map{|a|a}
    elsif value = list
      @api.client.list_timeline(value[:user], value[:list], count: 100, extended_tweet: true)
    end
  end

  def user
    paths = @url.path.split("/")
    if @url.host == "twitter.com" && paths.length == 2 && @url.path != "/search"
      paths.last
    end
  end

  def search
    return nil if !@url.query

    query = CGI::parse(@url.query)
    if @url.host == "twitter.com" && @url.path == "/search" && query["q"]
      query["q"].first
    end
  end

  def list
    paths = @url.path.split("/")
    if @url.host == "twitter.com" && paths.length == 4 && paths[2] == "lists"
      {user: paths[1], list: paths.last}
    end
  end

  def hashtag
    paths = @url.path.split("/")
    if @url.host == "twitter.com" && paths.length == 3 && paths[1] == "hashtag"
      '#' + paths.last
    end
  end

  def shortcut(url)
    if hashtag = url.sub!(/^#/, '')
      url = "https://twitter.com/hashtag/#{hashtag}"
    elsif user = url.sub!(/^@/, '')
      url = "https://twitter.com/#{user}"
    end
    url
  end
end
