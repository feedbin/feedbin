class PercolateDestroy
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(action_id)
    options = {
      index: Entry.index_name,
      type: ".percolator",
      id: action_id,
    }
    $search.each do |_, client|
      client.delete(options)
    end
  rescue Elasticsearch::Transport::Transport::Errors::NotFound
  end
end
