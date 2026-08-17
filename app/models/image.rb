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
  # website_favicon and website_touch_icon are separate providers for the same
  # host on purpose. Pipeline::Find#unchanged? keys on (provider, provider_id,
  # original_fingerprint, variant), and (provider, provider_id) is unique --
  # so collapsing them would let whichever preset crawled last own the row's
  # original_fingerprint, and the other would short-circuit forever on a
  # fingerprint belonging to a different variant's object.
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

  # The data JSON's schema, so readers get real methods instead of reaching
  # into the hash with string keys at every call site.
  store_accessor :data, :legacy_storage_url, :final_url, :etag, :last_modified, :preset

  scope :entry_images, -> { where(provider: %i[entry_link_preview entry_preview]) }

  # What an entry's deletion takes with it. Wider than entry_images because
  # episode artwork (entry_icon) is entry-owned too. These are deliberately
  # two scopes, not one: entry_images is also Dedupe's and ReuseRules' lookup
  # scope, and its narrowness is what stops an icon crawl from deduping onto
  # an entry-preview row.
  scope :entry_owned, -> { where(provider: %i[entry_link_preview entry_preview entry_icon]) }

  before_save :fingerprint_url

  # Identity is (url, variant), where variant is the output geometry
  # ("542x304"). One URL rendered at two sizes is two stored objects — the
  # fingerprint drives dedup lookups, and folding the variant in here keeps
  # storage_path variant-safe by extension: the sweep's survivor check keys
  # on storage_path, and both storage_path_for (via this fingerprint) and
  # content_storage_path_for (directly) fold the variant into it.
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
    path_for(Digest::MD5.hexdigest("#{variant}|#{original_fingerprint.to_s.delete("-")}"), extension)
  end

  def self.path_for(fingerprint, extension)
    File.join(fingerprint[0..2], "#{fingerprint}.#{extension}")
  end

  # A uuid column reads back dashed ("a1b2c3d4-..."); every fingerprint we
  # compute is 32 bare hex characters. Comparing them directly is silently
  # always false, which would make every icon look changed on every crawl --
  # the exact cost content-addressing exists to avoid. The database comparison
  # in a where() clause is safe because Postgres casts on the way in; only
  # Ruby-side comparison needs this.
  def self.same_fingerprint?(one, other)
    return false if one.blank? || other.blank?
    one.to_s.delete("-").casecmp?(other.to_s.delete("-"))
  end

  # The public URL for a stored object. Nil until R2_IMAGE_HOST is set, which
  # is what keeps the read path on the legacy fallback during a transition.
  def self.r2_url(storage_path)
    return nil if storage_path.blank?
    host = ENV["R2_IMAGE_HOST"]
    return nil if host.blank?
    host = "https://#{host}" unless host.match?(%r{\Ahttps?://})
    [host.chomp("/"), storage_path].join("/")
  end

  # The R2 write side, owned here so the deploy switch has one definition:
  # the pipeline writes and the sweep deletes iff the bucket is configured,
  # and they must flip together.
  def self.r2_bucket
    ENV["R2_BUCKET_IMAGES"]
  end

  def self.r2_enabled?
    r2_bucket.present?
  end

  def self.r2_client
    Fog::Storage.new(STORAGE_R2)
  end

  # Upsert keyed by (provider, provider_id). Not create_or_find_by: the
  # find-then-save shape is what lets an existing row be updated in place
  # rather than rescued. One retry, not an open loop -- the second pass finds
  # the row the racing writer inserted and updates it.
  def self.attach!(attributes)
    attributes = attributes.symbolize_keys
    attributes[:provider_id] = attributes[:provider_id].to_s
    tries = 0
    begin
      record = find_by(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id)) ||
        new(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id))
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
