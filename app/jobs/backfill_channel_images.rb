# One-time avatar migration from cached channel metadata. Run after
# BackfillFeedChannelIds. No YouTube API calls; the normal image pipeline
# downloads the advertised thumbnails and attaches the shared channel row.
class BackfillChannelImages
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  BATCH_SIZE = 500
  DELAY = 10

  # Counts include channels without usable thumbnails and failed downloads.
  # Check again after the image queues drain; scheduling is not completion.
  #
  # where.missing, not where.not(provider_id: subquery): NOT IN never becomes
  # an anti-join in Postgres, so it hashes every embed_icon provider_id per
  # query and rescans images per row once that hash outgrows work_mem. The
  # LEFT JOIN rides index_images_on_provider_and_provider_id instead.
  def self.pending
    Embed.youtube_channel.where.missing(:channel_image)
  end

  # after_id is exclusive, finish_id inclusive. Arel, not a SQL fragment:
  # the anti-join brings images into the query, and a bare "id" is ambiguous
  # once both tables are in scope.
  def self.window(after_id, finish_id)
    id = Embed.arel_table[:id]
    pending.where(id.gt(after_id)).where(id.lteq(finish_id))
  end

  # A fixed upper bound keeps the run finite while new channels are
  # harvested. Supply a small cutoff for a trial, or reuse the logged
  # last_id to resume an interrupted run. batch_size and delay are the
  # operator's rate knobs: the image queues are shared with live crawling,
  # so a flooded run can be restarted slower without a deploy.
  def perform(after_id = 0, finish_id = nil, batch_size = BATCH_SIZE, delay = DELAY)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    # Clamp: limit(0) returns nothing and ends the chain, which reads
    # exactly like a finished run.
    batch_size = [batch_size.to_i, 1].max
    delay = [delay.to_i, 0].max

    finish_id ||= Embed.youtube_channel.maximum(:id)
    return unless finish_id

    channels = self.class.window(after_id, finish_id).order(:id).limit(batch_size).to_a
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
    if channels.size == batch_size
      self.class.perform_in(delay, last_id, finish_id, batch_size, delay)
    end
  end
end
