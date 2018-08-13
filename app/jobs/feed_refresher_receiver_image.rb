class FeedRefresherReceiverImage
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(public_id, url)
    entry = Entry.find_by_public_id!(public_id)
    if entry.published > 4.weeks.ago && entry.data["itunes_image_processed"].nil?
      data = entry.data || {}
      data["itunes_image"] = url
      entry.update(data: data)
      ItunesImage.perform_async(entry.id, entry.data["itunes_image"])
    end
  rescue ActiveRecord::RecordNotFound
  end
end
