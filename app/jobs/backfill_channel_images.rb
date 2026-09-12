# One-time avatar migration from cached channel metadata. Run after
# BackfillFeedChannelIds. No YouTube API calls; the normal image pipeline
# downloads the advertised thumbnails and attaches the shared channel row.
#
# Fan-out in the SidekiqHelper style: perform(nil, true) pushes one job per
# SidekiqHelper::BATCH_SIZE embed ids, with `at` timestamps spaced evenly
# over SPREAD. The image queues are shared with live crawling and every
# channel costs a download from YouTube, so the batches must not all land
# at once; the spread is the rate toward both.
class BackfillChannelImages
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  SPREAD = 12.hours

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

  # The pending channels whose embed id falls in one SidekiqHelper batch.
  # A hash condition, not a SQL fragment: the anti-join brings images into
  # the query, and a bare "id" is ambiguous once both tables are in scope.
  def self.batch_scope(batch)
    ids = new.build_ids(batch)
    pending.where(id: ids.first..ids.last)
  end

  # spread is in seconds; the operator's one rate knob, taken at schedule
  # time so a different pace needs no deploy.
  def perform(batch = nil, schedule = false, spread = SPREAD)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    if schedule
      build(spread)
    else
      update(batch)
    end
  end

  # Embed ids are shared with videos, so a batch of 5,000 ids holds fewer
  # channels than that. Reruns are safe: a stored channel leaves pending, and
  # image attachment upserts by provider/channel, so a channel scheduled
  # twice while in flight does not create duplicate rows.
  def build(spread)
    last_id = Embed.youtube_channel.maximum(:id)
    return unless last_id

    jobs = job_args(last_id, Embed.youtube_channel.minimum(:id))
    now = Time.now.to_f
    step = spread.to_f / jobs.size
    at = jobs.each_index.map { |index| now + (index * step) }

    # push_bulk slices the push itself and pairs each job with its `at`.
    Sidekiq::Client.push_bulk("args" => jobs, "class" => self.class, "at" => at)
  end

  def update(batch)
    channels = self.class.batch_scope(batch).order(:id).to_a
    scheduled = 0

    channels.each do |channel|
      if ImageCrawler::ChannelImage.schedule(channel, critical: false)
        scheduled += 1
      else
        logger.info "BackfillChannelImages: no thumbnail embed_id=#{channel.id} channel_id=#{channel.provider_id}"
      end
    end

    logger.info "BackfillChannelImages: batch=#{batch} scanned=#{channels.size} scheduled=#{scheduled} no_thumbnail=#{channels.size - scheduled}"
  end
end
