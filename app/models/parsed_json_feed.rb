class ParsedJSONFeed < ParsedFeed

  def feed
    @feed ||= JSON.load(@body)
  end

  def title
    @title ||= feed["title"]
  end

  def site_url
    @site_url ||= begin
      if feed["home_page_url"]
        url = feed["home_page_url"]
      else
        url = url_from_host(feed_url)
      end
      url
    end
  end

  def self_url
    @self_url ||= begin
      if feed["feed_url"]
        url = feed["feed_url"]
        if !url.match(/^http/)
          url = URI.join(feed_url, url).to_s
        end
      end
      url
    rescue
      feed_url
    end
  end

  def hubs
    []
  end

  def author
    @author ||= begin
      if feed["author"] && feed["author"]["name"]
        feed["author"]["name"]
      else
        nil
      end
    end
  end

  def entries
    @entries ||= begin
      entries = []
      if feed["items"].respond_to?(:any?) && feed["items"].any?
        entries = feed["items"].map do |entry|
          ParsedJSONEntry.new(entry, base_url, author)
        end
        entries = entries.uniq { |entry| entry.public_id }
      end
      entries
    end
  end

  def valid?
    @valid ||= feed["version"].start_with?("https://jsonfeed.org/version/") && feed["title"]
  end

end
