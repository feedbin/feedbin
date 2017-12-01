class Source::MetaLinks < Source

  def call
    if cache(@url).format == :html
      find_links
    end
  end

  def find_links
    @options = document.search("link[rel='alternate']").each_with_object([]) do |link, array|
      if link_valid?(link)
        option = FeedOption.new(cache(@url).last_effective_url, link["href"], link["title"], "page_links")
        array.push(option)
      end
    end
    @options = @options.uniq { |option| option.title }
    @options = @options.uniq { |option| option.href }
    create_feeds!
  end

  private

  def document
    @document ||= Nokogiri::HTML(cache(@url).body)
  end

  def link_valid?(link)
    valid = false
    types = ["application/rss+xml", "application/atom+xml"]
    if link["type"] && link["href"]
      type = link["type"].strip.downcase
      valid = types.include?(type)
    end
    valid
  end

end