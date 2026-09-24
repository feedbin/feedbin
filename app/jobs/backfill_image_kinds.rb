# One-time: label rows written before images.kind existed. The preset in
# data is the only record of what the crawler knew when it stored the row,
# and every row since the 2026-08 recreate carries one, so the map below
# classifies all of history. Nothing outside this job derives kind from a
# preset: the crawler sets it at each call site.
#
# Fan-out in the SidekiqHelper style: perform(nil, true) pushes one job per
# SidekiqHelper::BATCH_SIZE ids at once, and the utility workers drain them
# in parallel. No delay and no chain, so the wall clock is the row work
# divided by the queue's concurrency.
class BackfillImageKinds
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  PRESET_KINDS = {
    "primary"        => :poster,
    "youtube"        => :poster,
    "twitter"        => :poster,
    "podcast"        => :cover_art,
    "podcast_feed"   => :cover_art,
    "channel_avatar" => :avatar,
    "favicon"        => :site_icon,
    "touch_icon"     => :site_icon
  }.freeze

  # Presets whose rows carry their kind from the call site, so there is
  # nothing to map and nothing to relabel. feed_icon writes avatar or
  # site_icon per source; micropost_avatar and icon (the copy of the
  # proxy's cache) write avatar.
  SELF_LABELED = %w[feed_icon micropost_avatar icon].freeze

  def perform(batch = nil, schedule = false)
    if schedule
      build
    else
      update(batch)
    end
  end

  # Rows inserted after the column landed already carry their kind, so a
  # bound taken at schedule time covers everything that needs labeling.
  # Reruns are safe: a row already at its mapped kind is skipped.
  def build
    last_id = Image.maximum(:id)
    return unless last_id

    job_args(last_id, Image.minimum(:id)).each_slice(10_000) do |jobs|
      Sidekiq::Client.push_bulk("args" => jobs, "class" => self.class)
    end
  end

  def update(batch)
    ids = build_ids(batch)
    scope = Image.where(id: ids.first..ids.last)
    preset = Image.data_projection("preset")

    # Stop rather than leave the default in place quietly: a row this map
    # cannot classify is a row the recreate should not have produced.
    unknown = scope.where(preset.not_in(PRESET_KINDS.keys + SELF_LABELED).or(preset.eq(nil))).distinct.pluck(preset)
    raise "BackfillImageKinds: unmapped presets #{unknown.inspect} in batch #{batch} (ids #{ids.first}..#{ids.last})" if unknown.any?

    # update_all, not update: updated_at is a view cache key and must move
    # only when the stored bytes move. Rows already at the right kind (the
    # column default covers most of the table) are left alone.
    updated = 0
    PRESET_KINDS.group_by { |_, kind| kind }.each do |kind, pairs|
      presets = pairs.map(&:first)
      updated += scope.where(preset.in(presets)).where.not(kind: kind).update_all(kind: Image.kinds.fetch(kind))
    end

    logger.info "BackfillImageKinds: batch=#{batch} updated=#{updated}"
  end
end
