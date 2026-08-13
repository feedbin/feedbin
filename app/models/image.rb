# t.bigint :provider,          null: false
# t.text   :provider_id,       null: false
# t.bigint :feed_id
# t.text   :url,               null: false
# t.text   :variant,           null: false
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

  # Identity is (url, variant), where variant is the output geometry
  # ("542x304"). One URL rendered at two sizes is two stored objects — the
  # fingerprint drives dedup lookups, and folding the variant in here keeps
  # storage_path variant-safe by extension: GC grouping and the advisory
  # locks key on storage_path, and both storage_path_for (via this
  # fingerprint) and content_storage_path_for (directly) fold the variant
  # into it.
  def self.url_fingerprint_for(url, variant)
    Digest::MD5.hexdigest("#{variant}|#{url.to_s.strip}")
  end

  # The extension is the stored object's format, which is a property of the
  # preset: webp for entry previews, png for the icon family (alpha, and the
  # ICO best-layer logic depends on it).
  def self.storage_path_for(url, variant, extension = "webp")
    path_for(url_fingerprint_for(url, variant), extension)
  end

  # The icon family's stored-object identity, in contrast to storage_path_for's:
  # these sources mutate under a stable URL (/favicon.ico serves new bytes; a
  # channel changes its avatar), so the URL answers "have we seen this source?"
  # and only the bytes answer "which object is this?".
  def self.content_storage_path_for(original_fingerprint, variant, extension)
    path_for(Digest::MD5.hexdigest("#{variant}|#{original_fingerprint}"), extension)
  end

  def self.path_for(fingerprint, extension)
    File.join(fingerprint[0..2], "#{fingerprint}.#{extension}")
  end

  # Upsert keyed by (provider, provider_id). Not create_or_find_by: every
  # call site runs inside Image.with_storage_lock's transaction, so a unique
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

  # Serializes attach vs. garbage collection for one stored object. The object
  # is the shared resource -- one path can be referenced by rows from several
  # providers and several URLs -- so the path is the lock key.
  def self.with_storage_lock(storage_path, &block)
    with_storage_locks([storage_path], &block)
  end

  # Takes every lock in one sorted acquisition so concurrent multi-lock
  # holders (garbage collection batches) cannot deadlock each other.
  # `execute`, not `select_all`: pg_advisory_xact_lock returns void, a type
  # ActiveRecord's result decoder warns about (unknown OID 2278); the raw
  # result is discarded either way.
  def self.with_storage_locks(storage_paths)
    keys = storage_paths.map(&:to_s).uniq.sort
    transaction do
      connection.execute(sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtextextended(key, 0)) FROM unnest(ARRAY[?]) AS key", keys]))
      yield
    end
  end

  private

  def fingerprint_url
    self[:url_fingerprint] = self.class.url_fingerprint_for(url, variant)
  end
end
