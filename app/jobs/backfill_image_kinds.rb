# One-time: label rows written before images.kind existed. The preset in
# data is the only record of what the crawler knew when it stored the row,
# and every row since the 2026-08 recreate carries one, so the map below
# classifies all of history. Nothing outside this job derives kind from a
# preset: the crawler sets it at each call site.
class BackfillImageKinds
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  # icon is absent on purpose: that preset writes remote_files, never an
  # images row.
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

  BATCH_SIZE = 5_000
  DELAY = 1

  # after_id is exclusive, finish_id inclusive.
  def self.window(after_id, finish_id)
    id = Image.arel_table[:id]
    Image.where(id.gt(after_id)).where(id.lteq(finish_id))
  end

  # A fixed upper bound keeps the run finite while the crawler inserts.
  # Rows inserted after the column landed already carry their kind. Supply
  # a small cutoff for a trial, or the logged last_id to resume.
  def perform(after_id = 0, finish_id = nil, batch_size = BATCH_SIZE, delay = DELAY)
    batch_size = [batch_size.to_i, 1].max
    delay = [delay.to_i, 0].max

    finish_id ||= Image.maximum(:id)
    return unless finish_id

    ids = self.class.window(after_id, finish_id).order(:id).limit(batch_size).pluck(:id)
    return if ids.empty?

    last_id = ids.last
    batch = self.class.window(after_id, last_id)
    preset = Image.data_projection("preset")

    # Stop rather than leave the default in place quietly: a row this map
    # cannot classify is a row the recreate should not have produced.
    unknown = batch.where(preset.not_in(PRESET_KINDS.keys).or(preset.eq(nil))).distinct.pluck(preset)
    raise "BackfillImageKinds: unmapped presets #{unknown.inspect} between ids #{after_id} and #{last_id}" if unknown.any?

    # update_all, not update: updated_at is a view cache key and must move
    # only when the stored bytes move. Rows already at the right kind (the
    # column default covers most of the table) are left alone.
    updated = 0
    PRESET_KINDS.group_by { |_, kind| kind }.each do |kind, pairs|
      presets = pairs.map(&:first)
      updated += batch.where(preset.in(presets)).where.not(kind: kind).update_all(kind: Image.kinds.fetch(kind))
    end

    logger.info "BackfillImageKinds: scanned=#{ids.size} updated=#{updated} last_id=#{last_id} finish_id=#{finish_id}"

    if ids.size == batch_size
      self.class.perform_in(delay, last_id, finish_id, batch_size, delay)
    end
  end
end
