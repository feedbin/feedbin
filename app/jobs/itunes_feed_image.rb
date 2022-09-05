class ItunesFeedImage
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(feed_id, image = nil)
    feed_id = feed_id.to_s.split("-").first
    @feed = Feed.find(feed_id)
    @image = image

    if @image
      receive
    else
      schedule
    end
  rescue ActiveRecord::RecordNotFound
  end

  def schedule
    if url = @feed.options&.dig("itunes_image")
      name = Digest::SHA1.hexdigest(url)
      url = @feed.rebase_url(url)
      Sidekiq::Client.push(
        "args" => ["#{@feed.id}-#{name}-itunes", "podcast_feed", [url]],
        "class" => "Crawler::Image::FindImage",
        "queue" => "image_parallel",
        "retry" => false
      )
    end
  end

  def receive
    @feed.update(custom_icon: @image["processed_url"], custom_icon_format: "square")
  end
end
