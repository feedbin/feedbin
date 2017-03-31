class FeedOptions

  def initialize(html, url)
    @html = html
    @url = url
  end

  def document
    @document ||= Nokogiri::HTML(@html)
  end

  def perform
    @perform ||= begin
      options = document.search("link[rel='alternate']").each_with_object([]) do |link, array|
        if link_valid?(link)
          option = FeedOption.new(@url, link["href"], link["title"])
          array.push(option)
        end
      end
      options.uniq { |option| option.title }
      options.uniq { |option| option.href }
    end
  end

  private

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