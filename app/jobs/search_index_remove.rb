class SearchIndexRemove
  include Sidekiq::Worker

  def perform(ids)
    data = ids.map { |id|
      {delete: {_id: id}}
    }
    $search.each do |_, client|
      client.bulk(
        index: Entry.index_name,
        type: Entry.document_type,
        body: data
      )
    end
    Sidekiq::Client.push(
      "args" => [ids],
      "class" => "SearchIndexRemoveAlt",
      "queue" => "worker_slow_search_alt",
      "retry" => false
    )
  end
end
