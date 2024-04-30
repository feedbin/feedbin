class EntryDeleterScheduler
  include Sidekiq::Worker
  include SidekiqHelper

  def perform
    return unless queue_empty?(Search::SearchServerSetup.get_sidekiq_options["queue"])

    Feed.select(:id).find_in_batches(batch_size: 10_000) do |feeds|
      Sidekiq::Client.push_bulk(
        "args" => feeds.map { |feed| feed.attributes.values },
        "class" => EntryDeleter
      )
    end
  end
end
