class BigBatch
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a

    Entry.where(id: ids, published: nil).each do |entry|
      if entry.original.present? && entry.original['published'].present?
        published = Time.parse(entry.original['published'])

        entry.update_attribute(:published, published)

        starred_entries = StarredEntry.where(entry_id: entry.id, published: nil)
        unread_entries = UnreadEntry.where(entry_id: entry.id, published: nil)
        if starred_entries.present?
          starred_entries.update_all(published: published)
        end
        if unread_entries.present?
          unread_entries.update_all(published: published)
        end
      end
    end

  end

end