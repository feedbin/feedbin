class FeedOption
  attr_reader :source

  def initialize(base_url, href, title = nil, source = "unspecified")
    @base_url = base_url
    @href = href
    @title = title
    @source = source
  end

  def href
    @href_result ||= begin
      result = @href.strip
      result = result.gsub(/^feed:/, "http:")
      unless result.start_with?("http")
        result = URI.join(@base_url, result).to_s
      end
      result
    end
  end

  def title
    @title_result ||= @title.respond_to?(:gsub) ? @title.gsub(/\s*(RSS[\s0-9\.]*|Atom)/i, "") : @href
  end
end
