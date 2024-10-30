# t.bigint :provider,          null: false
# t.text   :provider_id,       null: false
# t.text   :url,               null: false
# t.uuid   :url_fingerprint,   null: false
# t.text   :storage_url,       null: false
# t.uuid   :image_fingerprint, null: false
# t.bigint :width,             null: false
# t.bigint :height,            null: false
# t.text   :placeholder_color, null: false
# t.jsonb  :data,              null: false, default: {}
# t.jsonb  :settings,          null: false, default: {}

class Image < ApplicationRecord
  enum :provider, {
    entry_icon:         0,     # entry specific icon (microposts with avatar, twitter, podcasts, youtube)
    entry_link_preview: 1,     # link preview image
    entry_preview:      2,     # main preview image
    feed_icon:          3,     # feed-level icon (mastodon, podcast, youtube, twitter)
    remote_file:        4,     # adhoc images
    website_favicon:    5,     # favicon
    website_touch_icon: 6,     # apple touch icon
  }, prefix: true

  normalizes :url, with: -> url { url.strip }

  scope :feed_icons,   -> { where(provider: %i[feed_icon website_favicon website_touch_icon]) }
  scope :entry_icons,  -> { where(provider: %i[entry_icon website_favicon website_touch_icon]) }
  scope :entry_images, -> { where(provider: %i[entry_link_preview entry_preview]) }

  before_save :fingerprint_url

  private

  def fingerprint_url
    self[:url_fingerprint] = Digest::MD5.hexdigest(url)
  end

end
