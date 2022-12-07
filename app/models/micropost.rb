class Micropost
  attr_reader :data

  def initialize(data, title = nil, feed: nil)
    @data = data
    unless @data&.dig("json_feed").nil?
      @data = @data.dig("json_feed")
    end
    @title = title
    @feed = feed
  end

  def valid?
    @data&.respond_to?(:dig) && author_profile? && !title?
  end

  def author_avatar
    @data.dig("author", "avatar") || @data.dig("authors", 0, "avatar") || @feed&.options&.dig("image", "url")
  end

  def author_url
    @data.dig("author", "url") || @data.dig("authors", 0, "url") || @feed&.options&.dig("image", "link")
  end

  def author_name
    @data.dig("author", "name") || @data.dig("authors", 0, "name") || @feed&.options&.dig("image", "title")
  rescue
    nil
  end

  def author_username
    @data.dig("author", "_microblog", "username") || @data.dig("author", "_instagram", "username") || @data.dig("authors", 0, "_instagram", "username") || feed_username
  rescue
    nil
  end

  def author_display_username
    "@#{author_username}"
  end

  def url
    "https://micro.blog/#{author_username}/#{id}"
  end

  def source
    if @data.dig("author", "_microblog")
      :microblog
    elsif @data.dig("author", "_instagram") || @data.dig("authors", 0, "_instagram")
      :instagram
    end
  end

  def microblog?
    source == :microblog
  end

  def instagram?
    source == :instagram
  end

  private

  def feed_username
    link = @feed&.options&.dig("image", "link")
    return if link.nil?
    link = link.split("/").find { _1.start_with?("@") }
    return if link.nil?
    link.delete_prefix("@")
  end

  def id
    @data.dig("id")
  end

  def author_profile?
    !!(author_name && author_username)
  end

  def title?
    @title.present?
  end
end
