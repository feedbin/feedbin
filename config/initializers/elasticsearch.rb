Elasticsearch::Model.client = Elasticsearch::Client.new log: true
if Rails.env.development?
  Elasticsearch::Model.client.transport.tracer = ActiveSupport::Logger.new('log/elasticsearch.log')
end


if !Entry.__elasticsearch__.client.indices.exists(index: Entry.index_name)
  Entry.__elasticsearch__.client.indices.create({
    index: Entry.index_name,
    body: {
      settings: Entry.settings.to_hash,
      mappings: Entry.mappings.to_hash
    }
  }) rescue nil
end
