class TwitterLinkImage
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(entry_id, page_url = nil, processed_url = nil)
    @entry = Entry.find(entry_id)
    if processed_url
      receive(processed_url)
    else
      schedule(page_url)
    end
  rescue ActiveRecord::RecordNotFound
  end

  def schedule(page_url)
    Sidekiq::Client.push(
      "args" => [@entry.id, @entry.feed_id, page_url, @entry.public_id],
      "class" => "TwitterLinkImage",
      "queue" => "images",
      "retry" => false
    )
  end

  def receive(processed_url)
    entry = Entry.find(@entry.id)
    entry.data["twitter_link_image_processed"] = processed_url
    entry.save!
  end
end
