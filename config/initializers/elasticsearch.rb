Elasticsearch::Model.client = Elasticsearch::Client.new log: true
if Rails.env.development?
  Elasticsearch::Model.client.transport.tracer = ActiveSupport::Logger.new('log/elasticsearch.log')
end
Entry.__elasticsearch__.create_index!