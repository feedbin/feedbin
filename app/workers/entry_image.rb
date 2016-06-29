class EntryImage
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(entry_id, image = nil)
    @entry = Entry.find(entry_id)
    @image = image
    if image
      receive
    else
      schedule
    end
  rescue ActiveRecord::RecordNotFound
  end

  def schedule
    Sidekiq::Client.push(
      'args'  => [@entry.id, @entry.feed_id, @entry.url, @entry.fully_qualified_url, @entry.feed.site_url, @entry.content],
      'class' => 'FindImage',
      'queue' => 'image'
    )
  end

  def receive
    @entry.update_attributes(image: @image)
  end

end
