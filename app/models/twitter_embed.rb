class TwitterEmbed

  attr_reader :url

  def initialize(url)
    @url = url
  end

  def name
    data.dig("author_name")
  end

  def screen_name
    "@#{user}"
  end

  def tweet_url
    data.dig("url")
  end

  def date
    Date.parse document.search("blockquote > a").text
  end

  def content
    document.search("p").to_s
  end

  def profile_image_url
    "https://twitter.com/#{user}/profile_image?size=bigger"
  end

  def author_url
    data.dig("author_url")
  end

  private

    TWITTER_URL = "https://publish.twitter.com/oembed"

    def user
      @user ||= data.dig("author_url") && data.dig("author_url").split("/").last
    end

    def document
      @document ||= Nokogiri::HTML5.fragment(data.dig("html"))
    end

    def data
      @data ||= begin
        options = {
          params: {
            url: url,
            omit_script: true
          }
        }
        HTTP.get(TWITTER_URL, options).parse
      end
    end

end