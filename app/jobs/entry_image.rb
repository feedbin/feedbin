class EntryImage
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(entry_id, image = nil)
    @entry = Entry.find(entry_id)
    @image = image
    if @image
      receive
    else
      schedule
    end
  rescue ActiveRecord::RecordNotFound
  end

  def schedule
    unless @entry.processed_image?
      options = build_options
      Sidekiq::Client.push(
        "args" => EntryImage.build_find_image_args(@entry, options),
        "class" => "FindImage",
        "queue" => "images",
        "retry" => false,
      )
    end
  end

  def build_options
    options = {}
    if @entry.tweet?
      tweet = @entry.tweet.retweeted_status? ? @entry.tweet.retweeted_status : @entry.tweet
      if tweet.media?
        options["urls"] = [tweet.media.first.media_url_https.to_s]
      elsif tweet.urls?
        options["urls"] = tweet.urls.map { |url| url.expanded_url.to_s }
      end
    end
    options
  end

  def receive
    @entry.update_attributes(image: @image)
  end

  def self.build_find_image_args(entry, options = {})
    [entry.id, entry.feed_id, entry.url, entry.fully_qualified_url, entry.feed.site_url, entry.content, entry.public_id, options]
  end
end
