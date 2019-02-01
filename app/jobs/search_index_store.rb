class SearchIndexStore
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(klass, id, update = false)
    klass = klass.constantize
    record = klass.find(id)
    index(record, klass)
    percolate(record, klass) unless update
  rescue ActiveRecord::RecordNotFound
  end

  def index(record, klass)
    data = {
      index: klass.index_name,
      type: klass.document_type,
      id: record.id,
      body: record.as_indexed_json,
    }
    $search.each do |_, client|
      client.index(data)
    end
  end

  def percolate(record, klass)
    result = klass.__elasticsearch__.client.percolate(
      index: klass.index_name,
      type: klass.document_type,
      percolate_format: "ids",
      body: {
        doc: record.as_indexed_json,
        filter: {
          term: {feed_id: record.feed_id},
        },
      },
    )

    ids = result["matches"].map(&:to_i)
    if ids.present?
      ActionsPerform.perform_async(record.id, ids)
    end
  end
end
