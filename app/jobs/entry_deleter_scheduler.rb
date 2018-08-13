class EntryDeleterScheduler
  include Sidekiq::Worker

  def perform
    Feed.select(:id).find_in_batches(batch_size: 10_000) do |feeds|
      Sidekiq::Client.push_bulk(
        "args" => feeds.map { |feed| feed.attributes.values },
        "class" => "EntryDeleter",
        "queue" => "worker_slow",
        "retry" => false,
      )
    end
  end
end
