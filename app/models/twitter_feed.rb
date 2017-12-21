class TwitterFeed
  attr_reader :url

  def initialize(url, token, secret, screen_name = nil)
    url = url.strip
    url = shortcut(url)
    if url.start_with?("twitter.com")
      url = "https://#{url}"
    end
    @screen_name = screen_name
    @url = URI.parse(url)
    @api = TwitterAPI.new(token, secret)
  end

  def feed
    type = nil
    tweets = nil
    options = {}
    url = nil

    default_options = {
      count: 100,
      tweet_mode: "extended"
    }
    if value = user
      type = :user
      tweets = @api.client.user_timeline(value, default_options.merge(exclude_replies: true))
      options["twitter_user"] = @api.client.user(value)
    elsif value = search || value = hashtag
      type = :search
      tweets = @api.client.search(value, default_options.merge(result_type: "recent", include_entities: true)).map{|a|a}
    elsif value = list
      type = :list
      tweets = @api.client.list_timeline(value[:user], value[:list], default_options)
    elsif value = home
      type = :home
      tweets = @api.client.home_timeline(default_options)
      @url.query = "screen_name=#{value}"
    end
    if tweets && value
      ParsedTwitterFeed.new(@url.to_s, tweets, type, value, options)
    end
  end

  def home
    if @url.host == "twitter.com" && ["", "/"].include?(@url.path)
      @screen_name
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
