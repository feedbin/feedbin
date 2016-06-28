class EntryImage
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :image

  def perform(entry_id)
    entry = Entry.find(entry_id)
    feed = entry.feed
    if image = EntryCandidates.new(entry, feed).find_image
      entry.update_attributes(image: image)
      Librato.increment 'entry_image.create.from_entry'
    end
    if image.nil?
      if image = PageCandidates.new(entry, feed).find_image
        entry.update_attributes(image: image)
        Librato.increment 'entry_image.create.from_page'
      end
    end
  rescue ActiveRecord::RecordNotFound
  end

end
