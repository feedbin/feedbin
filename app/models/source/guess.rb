class Source::Guess < Source
  def find
    url = Addressable::URI.parse(response.url)
    ["/rss", "/feed"].each do |path|
      guess = Addressable::URI.new(scheme: url.scheme, host: url.host, path: path).to_s
      feeds.push create_from_url!(guess)
    rescue Feedkit::Error
    end
  end
end
