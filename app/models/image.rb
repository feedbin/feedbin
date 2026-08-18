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
  # website_favicon and website_touch_icon stay separate providers:
  # (provider, provider_id) is unique and unchanged? keys on the row's
  # original_fingerprint, so a shared row would let one variant's crawl
  # short-circuit the other's forever.
  enum :provider, {
    entry_icon:         0,     # entry specific icon (microposts with avatar, twitter, podcasts, youtube)
    entry_link_preview: 1,     # link preview image
    entry_preview:      2,     # main preview image
    feed_icon:          3,     # feed-level icon (mastodon, podcast, youtube, twitter)
    remote_file:        4,     # adhoc images
    embed_icon:         5,     # embed-provider icon keyed by that provider's own id (YouTube channel avatars)
    website_favicon:    6,     # a host's favicon, keyed by host ("medium.com")
    website_touch_icon: 7,     # a host's apple-touch-icon, keyed by host; deliberately its own provider, see below
  }, prefix: true

  normalizes :url, with: -> url { url.strip }

  # The data JSON's schema as real accessors.
  store_accessor :data, :legacy_storage_url, :final_url, :etag, :last_modified, :preset

  # One data key as a SQL projection, for plucks that skip instantiating
  # rows. Restricted to store_accessor's registry so a renamed key fails
  # loudly. Arel quotes the key; it is never interpolated.
  def self.data_projection(key)
    unless stored_attributes[:data].include?(key.to_sym)
      raise ArgumentError, "not a data accessor: #{key.inspect}"
    end
    Arel::Nodes::InfixOperation.new("->>", arel_table[:data], Arel::Nodes.build_quoted(key.to_s))
  end

  scope :entry_images, -> { where(provider: %i[entry_link_preview entry_preview]) }

  # What an entry's deletion takes with it. Wider than entry_images, which
  # doubles as Dedupe's and ReuseRules' lookup scope and must stay narrow so
  # an icon crawl cannot dedupe onto an entry-preview row.
  scope :entry_owned, -> { where(provider: %i[entry_link_preview entry_preview entry_icon]) }

  before_save :fingerprint_url

  # Identity is (url, variant): one URL rendered at two sizes is two stored
  # objects. The variant folds into the fingerprint, and through it into
  # storage_path, which the sweep's survivor check keys on.
  def self.url_fingerprint_for(url, variant)
    Digest::MD5.hexdigest("#{variant}|#{url.to_s.strip}")
  end

  # The extension is a preset property: jpg for previews and podcast
  # artwork, png for the icon family (alpha; ICO best-layer selection needs it).
  def self.storage_path_for(url, variant, extension = "jpg")
    path_for(url_fingerprint_for(url, variant), extension)
  end

  # Identity for sources that mutate under a stable URL (/favicon.ico, a
  # channel avatar): the URL answers "seen this source?", only the bytes
  # answer "which object is this?".
  def self.content_storage_path_for(original_fingerprint, variant, extension)
    path_for(Digest::MD5.hexdigest("#{variant}|#{original_fingerprint.to_s.delete("-")}"), extension)
  end

  # A storage key: the unified object name and the public URL path, sharded
  # on the first three characters.
  def self.path_for(fingerprint, extension)
    "#{fingerprint[0..2]}/#{fingerprint}.#{extension}"
  end

  # uuid columns read back dashed; computed fingerprints are bare hex, so
  # direct comparison is silently always false. where() is safe (Postgres
  # casts on the way in); only Ruby-side comparison needs this.
  def self.same_fingerprint?(one, other)
    return false if one.blank? || other.blank?
    one.to_s.delete("-").casecmp?(other.to_s.delete("-"))
  end

  # The public URL for a stored object. Nil until UNIFIED_IMAGE_HOST is set,
  # which keeps the read path on the legacy fallback.
  def self.unified_url(storage_path)
    return nil if storage_path.blank?
    host = ENV["UNIFIED_IMAGE_HOST"]
    return nil if host.blank?

    # hints is positional -- as a keyword it lands in the hash as :hints and
    # the scheme silently defaults to http.
    base = Addressable::URI.heuristic_parse(host, {scheme: "https"})

    # A relative reference resolves against the base's directory, so the
    # path must end in a slash or join replaces the last segment.
    base.path += "/" unless base.path.end_with?("/")
    base.join(storage_path).to_s
  end

  # One definition for the write-side switch: the pipeline writes and the
  # sweep deletes iff the bucket is configured, and they must flip together.
  def self.unified_bucket
    ENV["UNIFIED_BUCKET_IMAGES"]
  end

  def self.unified_enabled?
    unified_bucket.present?
  end

  def self.unified_client
    Fog::Storage.new(STORAGE_UNIFIED)
  end

  # Upsert keyed by (provider, provider_id). One retry: the second pass
  # finds the row a racing writer inserted and updates it in place.
  def self.attach!(attributes)
    attributes = attributes.symbolize_keys
    attributes[:provider_id] = attributes[:provider_id].to_s

    # fetch: a missing provider must not key the lookup on provider_id alone.
    key = {provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id)}

    tries = 0
    begin
      record = find_by(key) || new(key)
      record.assign_attributes(attributes)
      record.save!
      record
    rescue ActiveRecord::RecordNotUnique
      raise if (tries += 1) > 1
      retry
    end
  end

  private

  def fingerprint_url
    self[:url_fingerprint] = self.class.url_fingerprint_for(url, variant)
  end
end
