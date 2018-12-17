class Micropost
  attr_reader :data

  def initialize(data, title)
    @data = data
    @title = title
  end

  def valid?
    data && author_profile? && !title?
  end

  def author_avatar
    data.dig("author", "avatar")
  end

  def author_url
    data.dig("author", "url")
  end

  def author_name
    data.dig("author", "name")
  end

  def author_username
    data.dig("author", "_microblog", "username")
  end

  def author_display_username
    "@#{author_username}"
  end

  def url
    "https://micro.blog/#{author_username}/#{id}"
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
