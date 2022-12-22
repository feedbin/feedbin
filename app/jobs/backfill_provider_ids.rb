class BackfillProviderIds
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  def perform(batch)
    ids = build_ids(batch)
    entries = Entry.where(id: ids).select(:id, :data, :main_tweet_id)

    provider_id_data = {}
    provider_data = {}

    entries.each do |entry, hash|
      if id = entry.main_tweet_id
        provider_id_data[entry.id] = id
        provider_data[entry.id] = 0
      elsif id = entry.data.safe_dig("youtube_video_id")
        provider_id_data[entry.id] = id
        provider_data[entry.id] = 1
      end
    end

    if provider_id_data.present?
      Entry.update_multiple(column: :provider_id, data: provider_id_data)
      Entry.update_multiple(column: :provider, data: provider_data)
    end
  end

  def build
    jobs = job_args(Entry.last.id)
    Sidekiq::Client.push_bulk(
      "args" => jobs,
      "class" => self.class
    )
  end
end
