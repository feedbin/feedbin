# t.bigint :provider,          null: false
# t.text   :provider_id,       null: false
# t.bigint :feed_id
# t.text   :url,               null: false
# t.uuid   :url_fingerprint,   null: false
# t.uuid   :image_fingerprint, null: false
# t.text   :storage_path,      null: false
# t.bigint :width,             null: false
# t.bigint :height,            null: false
# t.bigint :bytesize,          null: false
# t.text   :placeholder_color, null: false
# t.jsonb  :data,              null: false, default: {}

class Image < ApplicationRecord
  enum :provider, {
    entry_icon:         0,     # entry specific icon (microposts with avatar, twitter, podcasts, youtube)
    entry_link_preview: 1,     # link preview image
    entry_preview:      2,     # main preview image
    feed_icon:          3,     # feed-level icon (mastodon, podcast, youtube, twitter)
    remote_file:        4,     # adhoc images
  }, prefix: true

  normalizes :url, with: -> url { url.strip }

  scope :entry_images, -> { where(provider: %i[entry_link_preview entry_preview]) }

  before_save :fingerprint_url

  def self.url_fingerprint_for(url)
    Digest::MD5.hexdigest(url.to_s.strip)
  end

  def self.storage_path_for(url)
    fingerprint = url_fingerprint_for(url)
    File.join(fingerprint[0..2], "#{fingerprint}.webp")
  end

  # Upsert keyed by (provider, provider_id). Not create_or_find_by: every
  # call site runs inside Image.with_url_lock's transaction, so a unique
  # violation would otherwise poison that outer transaction. The
  # requires_new: true save wraps it in a savepoint, scoping the violation
  # so the rescue/retry below can actually recover instead of raising
  # PG::InFailedSqlTransaction.
  def self.attach!(attributes)
    attributes = attributes.symbolize_keys
    attributes[:provider_id] = attributes[:provider_id].to_s
    record = find_by(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id)) ||
      new(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id))
    record.assign_attributes(attributes)
    transaction(requires_new: true) do
      record.save!
    end
    record
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Serializes attach vs. garbage collection for one stored object. The
  # fingerprint arrives dashed when read back from the uuid column and
  # undashed when freshly computed; normalize so both take the same lock.
  def self.with_url_lock(fingerprint, &block)
    with_url_locks([fingerprint], &block)
  end

  # Takes every lock in one sorted acquisition so concurrent multi-lock
  # holders (garbage collection batches) cannot deadlock each other.
  def self.with_url_locks(fingerprints)
    keys = fingerprints.map { _1.to_s.delete("-") }.uniq.sort
    transaction do
      connection.select_all(sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtextextended(key, 0)) FROM unnest(ARRAY[?]) AS key", keys]))
      yield
    end
  end

  private

  def fingerprint_url
    self[:url_fingerprint] = self.class.url_fingerprint_for(url)
  end
end
