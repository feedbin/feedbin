Elasticsearch::Model.client = Elasticsearch::Client.new(
  log: Rails.env.development?,
  transport_options: {
    ssl: { verify: false }
  }
)
$alt_search = begin
  if ENV['ELASTICSEARCH_ALT_URL']
    Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_ALT_URL'],
      transport_options: {
        ssl: { verify: false }
      }
    )
  else
    nil
  end
end
if Rails.env.development?
  Elasticsearch::Model.client.transport.tracer = ActiveSupport::Logger.new('log/elasticsearch.log')
  Entry.__elasticsearch__.create_index! rescue nil
end