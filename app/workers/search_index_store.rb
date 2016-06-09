class SearchIndexStore
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  Client = Elasticsearch::Client.new log: true
  if Rails.env.development?
    Client.transport.tracer = ActiveSupport::Logger.new('log/elasticsearch.log')
  end

  def perform(klass, id, update = false)
    klass = klass.constantize
    record = klass.find(id)
    body = record.as_indexed_json

    document = {
      index: Entry.index_name,
      type: Entry.document_type,
      id: record.id,
      body: body
    }

    Client.index(document)

    if !update
      result =  Client.percolate index: Entry.index_name, type: Entry.document_type, body: {doc: body}
      percolator_ids = result['matches'].map{ |match| match["_id"].to_i }
      if percolator_ids.present?
        ActionsPerform.perform_async(id, percolator_ids)
      end
    end

  rescue ActiveRecord::RecordNotFound
  end

end