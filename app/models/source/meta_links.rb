class Source::MetaLinks < Source
  def call
    if @config[:request].format == :html
      find_links
    end
  end

  def find_links
    @feed_options = document.search("link[rel='alternate']").each_with_object([]) { |link, array|
      if link_valid?(link)
        option = FeedOption.new(@config[:request].last_effective_url, link["href"], link["title"], "page_links")
        array.push(option)
      end
    }
    @feed_options = @feed_options.uniq { |option| option.title }
    @feed_options = @feed_options.uniq { |option| option.href }
    create_feeds!
  end

  private

  def document
    @document ||= Nokogiri::HTML(@config[:request].body)
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
