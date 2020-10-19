class SearchIndexStore
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(klass, id, update = false)
    entry = Entry.find(id)
    document = entry.search_data
    index(entry, document)
    percolate(entry, document, update)
  rescue ActiveRecord::RecordNotFound
  end

  def index(entry, document)
    data = {
      index: Entry.index_name,
      type: Entry.document_type,
      id: entry.id,
      body: document
    }
    $search.each do |_, client|
      client.index(data)
    end
  end

  def percolate(entry, document, update)
    result = Entry.__elasticsearch__.client.percolate(
      index: Entry.index_name,
      type: Entry.document_type,
      percolate_format: "ids",
      body: {
        doc: document,
        filter: {
          term: {feed_id: entry.feed_id}
        }
      }
    )

    ids = result["matches"].map(&:to_i)
    if ids.present?
      ActionsPerform.perform_async(entry.id, ids, update)
    end
  end
end
