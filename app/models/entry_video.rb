# Video => entries index, so a harvest that updates a video or channel avatar
# can mark the entries showing it edited.
class EntryVideo < ApplicationRecord
  belongs_to :entry

  # Returns the ids that weren't recorded for the entry before.
  def self.record(entry_id:, provider_ids:)
    return [] if provider_ids.empty?
    now = Time.current
    rows = provider_ids.uniq.map { {entry_id:, provider_id: it, created_at: now} }
    insert_all(rows, unique_by: [:provider_id, :entry_id], returning: [:provider_id]).rows.flatten
  end

  def self.bump_for_videos(provider_ids)
    return 0 if provider_ids.empty?
    bump(Entry.where(id: where(provider_id: provider_ids).select(:entry_id)))
  end

  # Never a nil query: every non-YouTube embed row's parent_id is nil.
  def self.bump_for_channel(channel_id)
    return 0 if channel_id.blank?
    videos = Embed.youtube_video.where(parent_id: channel_id).select(:provider_id)
    bump(Entry.where(id: where(provider_id: videos).select(:entry_id)))
  end

  # update_all: nothing rendered changed, so skip callbacks and re-rendering.
  def self.bump(entries)
    entries.update_all(["revision = revision + 1, edited_at = ?", Time.current])
  end
end
