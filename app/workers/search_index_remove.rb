class SearchIndexRemove
  include Sidekiq::Worker

  def perform(ids)
    ids = ids.map { |id| { id: id, type: 'entry' } }
    Entry.tire.index.bulk_delete(ids)
  end

end