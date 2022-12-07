class Micropost
  attr_reader :data

  def initialize(entry, feed)
    @entry = entry
    @feed = feed
  end

  def valid?
    @entry.data&.respond_to?(:dig) && author_profile? && !title?
  end

  def author_avatar
    @entry.data.dig("json_feed", "author", "avatar") || @entry.data.dig("json_feed", "authors", 0, "avatar") || @feed.options&.dig("image", "url")
  end

  def author_url
    @entry.data.dig("json_feed", "author", "url") || @entry.data.dig("json_feed", "authors", 0, "url") || @feed.options&.dig("image", "link")
  end

  def author_name
    @entry.data.dig("json_feed", "author", "name") || @entry.data.dig("json_feed", "authors", 0, "name") || @feed.options&.dig("image", "title")
  rescue
    nil
  end

  def author_username
    @entry.data.dig("json_feed", "author", "_microblog", "username") || @entry.data.dig("json_feed", "author", "_instagram", "username") || @entry.data.dig("json_feed", "authors", 0, "_instagram", "username") || feed_username
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
    if @entry.data.dig("json_feed", "author", "_microblog")
      :microblog
    elsif @entry.data.dig("json_feed", "author", "_instagram") || @entry.data.dig("json_feed", "authors", 0, "_instagram")
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
    link = @feed.options&.dig("image", "link")
    return if link.nil?
    link = link.split("/").find { _1.start_with?("@") }
    return if link.nil?
    link.delete_prefix("@")
  end

  def id
    @entry.data.dig("json_feed", "id")
  end

  def author_profile?
    !!(author_name && author_username)
  end

  def title?
    @title.present?
  end
end
