class Micropost
  attr_reader :data

  def initialize(data, title)
    @data = data
    @title = title
  end

  def valid?
    data&.respond_to?(:dig) && author_profile? && !title?
  end

  def author_avatar
    data.dig("author", "avatar") || data.dig("authors", 0, "avatar")
  end

  def author_url
    data.dig("author", "url") || data.dig("authors", 0, "url")
  end

  def author_name
    data.dig("author", "name") || data.dig("authors", 0, "name")
  rescue
    nil
  end

  def author_username
    data.dig("author", "_microblog", "username") || data.dig("author", "_instagram", "username") || data.dig("authors", 0, "_instagram", "username")
  end

  def author_display_username
    "@#{author_username}"
  end

  def url
    "https://micro.blog/#{author_username}/#{id}"
  end

  def source
    if data.dig("author", "_microblog")
      :microblog
    elsif data.dig("author", "_instagram") || data.dig("authors", 0, "_instagram")
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

  def id
    data.dig("id")
  end

  def author_profile?
    !!(author_name && author_username)
  end

  def title?
    @title.present?
  end
end
