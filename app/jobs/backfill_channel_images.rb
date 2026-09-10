# One-time avatar migration from cached channel metadata. Run after
# BackfillFeedChannelIds. No YouTube API calls; the normal image pipeline
# downloads the advertised thumbnails and attaches the shared channel row.
class BackfillChannelImages
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  BATCH_SIZE = 500

  # Counts include channels without usable thumbnails and failed downloads.
  # Check again after the image queues drain; scheduling is not completion.
  def self.pending
    Embed.youtube_channel.where.not(provider_id: Image.provider_embed_icon.select(:provider_id))
  end

  # after_id is exclusive, finish_id inclusive. A fixed upper bound keeps
  # the run finite while new channels are harvested. Supply a small cutoff
  # for a trial, or reuse the logged last_id to resume an interrupted run.
  def perform(after_id = 0, finish_id = nil)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    finish_id ||= Embed.youtube_channel.maximum(:id)
    return unless finish_id

    channels = self.class.pending.where("id > ? AND id <= ?", after_id, finish_id)
      .order(:id).limit(BATCH_SIZE).to_a
    scheduled = 0

    channels.each do |channel|
      if ImageCrawler::ChannelImage.schedule(channel)
        scheduled += 1
      else
        logger.info "BackfillChannelImages: no thumbnail embed_id=#{channel.id} channel_id=#{channel.provider_id}"
      end
    end

    last_id = channels.last&.id || after_id
    logger.info "BackfillChannelImages: scanned=#{channels.size} scheduled=#{scheduled} no_thumbnail=#{channels.size - scheduled} last_id=#{last_id} finish_id=#{finish_id}"

    # A retry can enqueue the same unstored channel again; image attachment
    # upserts by provider/channel, so reruns do not create duplicate rows.
    self.class.perform_in(10.seconds, last_id, finish_id) if channels.size == BATCH_SIZE
  end
end
