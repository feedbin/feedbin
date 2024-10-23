class Micropost
  attr_reader :data

  def initialize(data, title = nil, feed: nil)
    @data = data
    unless @data&.safe_dig("json_feed").nil?
      @data = @data.safe_dig("json_feed")
    end
    @title = title
    @feed = feed
  end

  def valid?
    @data&.respond_to?(:dig) && author_profile? && !title?
  end

  def author_avatar
    @data.safe_dig("author", "avatar") || @data.safe_dig("authors", 0, "avatar") || @feed&.options&.safe_dig("image", "url")
  end

  def author_url
    @data.safe_dig("author", "url") || @data.safe_dig("authors", 0, "url") || @feed&.options&.safe_dig("image", "link")
  end

  def author_name
    @data.safe_dig("author", "name") || @data.safe_dig("authors", 0, "name") || @feed&.options&.safe_dig("image", "title")
  rescue
    nil
  end

  def author_username
    @data.safe_dig("author", "_microblog", "username") || @data.safe_dig("author", "_instagram", "username") || @data.safe_dig("authors", 0, "_instagram", "username") || @data.safe_dig("authors", 0, "_social", "username") || feed_username
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
    if @data.safe_dig("author", "_microblog")
      :microblog
    elsif @data.safe_dig("author", "_instagram") || @data.safe_dig("authors", 0, "_instagram")
      :instagram
    elsif @data.safe_dig("authors", 0, "_social")
      :social
    end
  end

  def microblog?
    source == :microblog
  end

  def instagram?
    source == :instagram
  end

  def social?
    source == :social
  end

  def link_preview?
    return false unless data.safe_dig("saved_pages", data.safe_dig("urls")&.first).present?
    return false if data.safe_dig("saved_pages", data.safe_dig("urls")&.first, "result", "error")
    data.safe_dig("twitter_link_image_processed").present?
  end

  private

  def feed_username
    link = @feed&.options&.safe_dig("image", "link")
    return if link.nil?
    link = link.split("/").find { _1.start_with?("@") }
    return if link.nil?
    link.delete_prefix("@")
  end

  def id
    @data.safe_dig("id")
  end

  def author_profile?
    !!(author_name && author_username)
  end

  def title?
    @title.present?
  end
end
