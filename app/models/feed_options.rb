class FeedOptions
  def initialize(html, url)
    @html = html
    @url = url
  end

  def document
    @document ||= Nokogiri::HTML(@html)
  end

  def perform
    @links ||= begin
      options = document.search("link[rel='alternate']").each_with_object([]) do |link, array|
        if link_valid?(link)
          option = {
            href: format_href(link["href"]),
            title: format_title(link["title"]) || link["href"]
          }
          array.push(option)
        end
      end
      options.uniq { |link| link[:title] }
    end
  end

  private

  def format_title(title)
    title.respond_to?(:gsub) ? title.gsub(/\s*(RSS[\s0-9\.]*|Atom)/i, "") : title
  end

  def format_href(href)
    href = href.strip
    href = href.gsub(/^feed:/, 'http:')
    if !href.start_with?('http')
      href = URI.join(@url, href).to_s
    end
    href
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