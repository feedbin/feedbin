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
    if !@entry.processed_image?
      Sidekiq::Client.push(
        'args'  => EntryImage.build_find_image_args(@entry),
        'class' => 'FindImage',
        'queue' => 'images',
        'retry' => false
      )
    end
  end

  def receive
    @entry.update_attributes(image: @image)
  end

  def self.build_find_image_args(entry)
    [entry.id, entry.feed_id, entry.url, entry.fully_qualified_url, entry.feed.site_url, entry.content]
  end

end
