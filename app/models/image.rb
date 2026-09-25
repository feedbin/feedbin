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

  # What the picture is, independent of provider. provider keys the row
  # (feed id, entry id, channel id, host); kind says what the picture is. A
  # YouTube channel avatar is embed_icon + avatar: keyed by channel because
  # a playlist feed mixes channels, while still rendering as the feed's icon.
  # Only the crawler knows which parser field a URL came from, so kind is
  # set at each call site and never derived from the preset or the URL.
  #
  # The column default (poster) exists so the ADD COLUMN was a catalog
  # change, not for callers: attach! insists on an explicit kind.
  enum :kind, {
    cover_art: 0,     # a work: <itunes:image>, per-episode art
    avatar:    1,     # a person or a channel: YouTube channel, Mastodon account, micropost author
    site_icon: 2,     # a site: favicon, apple-touch-icon
    poster:    3,     # stands for the item: lead image, video thumbnail, og:image of a linked page
  }, prefix: true

  # The frame this picture renders in. A person or a channel is round;
  # a work, a site, or a poster is square. The only reader of kind for
  # layout, so the shape has one derivation.
  def icon_format
    kind_avatar? ? "round" : "square"
  end

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

  # The website_favicon rows for the hosts of a collection's Pages entries,
  # keyed by lower-cased host. Pages entries key on their own host rather
  # than the feed's, so no feed preload reaches them; the entry list
  # resolves the whole page in one query and hands the map down as a local.
  def self.favicons_for_entries(entries)
    hosts = Array(entries).filter_map { it.hostname&.downcase if it.feed&.pages? }.uniq
    return {} if hosts.empty?
    provider_website_favicon.where(provider_id: hosts).index_by(&:provider_id)
  end

  # A micropost author's avatar row for this url, or nil. Any one will do:
  # take, not the newest, which would read and sort the row of every entry
  # ever attached to the url. One indexed read on url_fingerprint; the
  # preset comes out of data through Arel, nothing is interpolated.
  def self.avatar_row(url)
    variant = ImageCrawler::Image.new(preset_name: "micropost_avatar").variant
    where(url_fingerprint: url_fingerprint_for(url, variant)).where(data_projection("preset").eq("micropost_avatar")).take
  end

  # A micropost avatar by the url it came from, for a reader without a row
  # of its own: the micro.blog replies dialog, and a micropost whose row has
  # not landed. A miss goes through camo, so a live url still renders.
  # Tweets never come here: they stay on RemoteFile.
  def self.avatar_url(url)
    return nil if url.blank?
    avatar_row(url.to_s)&.public_url || RemoteFile.camo_url(url.to_s)
  end

  # A LEFT JOIN from table to its images rows for provider, keyed by key: a
  # text node, because provider_id is text (see as_text). A caller keeps
  # the rows with no match by testing arel_table[:id] for NULL, an
  # anti-join. Not NOT IN, which Postgres never plans as an anti-join, and
  # not where.missing, which compares text to bigint. The join rides
  # index_images_on_provider_and_provider_id.
  def self.outer_join(table, provider:, key:)
    table.join(arel_table, Arel::Nodes::OuterJoin).on(
      arel_table[:provider].eq(providers.fetch(provider)).and(arel_table[:provider_id].eq(key))
    )
  end

  # CAST(node AS text). Arel.sql carries only the type keyword, never a value.
  def self.as_text(node)
    Arel::Nodes::NamedFunction.new("CAST", [node.as(Arel.sql("text"))])
  end

  # The columns a row takes from a row that already stores its picture:
  # attaching is a database write that shares the stored object. Dedupe
  # and MicropostAvatar attach this way.
  def self.stored_object_attributes(record)
    %i[variant image_fingerprint original_fingerprint storage_path width height bytesize placeholder_color].index_with { record.public_send(it) }
  end

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
  def self.normalize_fingerprint(fingerprint)
    fingerprint.to_s.delete("-").downcase
  end

  def self.same_fingerprint?(one, other)
    return false if one.blank? || other.blank?
    normalize_fingerprint(one) == normalize_fingerprint(other)
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

  # Production has no image path but the unified store once the legacy read
  # fallback is gone, so a boot without either switch fails here rather than
  # blank every image on the host. Arguments exist so a test can drive it.
  def self.check_unified_config!(env: Rails.env, vars: ENV)
    return unless env.production?

    %w[UNIFIED_BUCKET_IMAGES UNIFIED_IMAGE_HOST].each do |name|
      raise "#{name} must be set in production: the unified store is the only image path" if vars[name].blank?
    end
    nil
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

    # fetch: the column default would otherwise label a caller's omission as
    # a poster and nothing downstream could tell.
    attributes.fetch(:kind)

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

  # The public URL of the stored object, or nil until UNIFIED_IMAGE_HOST is
  # set. The icon family's readers call this on the record they resolved.
  def public_url
    self.class.unified_url(storage_path)
  end

  private

  def fingerprint_url
    self[:url_fingerprint] = self.class.url_fingerprint_for(url, variant)
  end
end
