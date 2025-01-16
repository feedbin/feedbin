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
    avatar:             0,     # entry specific icon (microposts, mastodon, podcast, youtube, twitter)
    preview_entry:      1,     # main preview image
    preview_link:       2,     # link preview image
    remote_file:        3,     # adhoc images
    website_favicon:    4,     # favicon
    website_touch_icon: 5,     # apple touch icon
  }, prefix: true

  has_many :image_tags
  has_many :entries, through: :image_tags, source: :imageable, source_type: "Entry"
  has_many :feeds, through: :image_tags, source: :imageable, source_type: "Feed"

  scope :favicons, -> { where(provider: %i[website_favicon website_touch_icon]) }
  scope :avatars,  -> { where(provider: %i[avatar]) }

  before_validation :generate_columns

  store_accessor :settings, :original_storage_url, :final_url

  private

  def generate_columns
    self[:url]                 = url.strip
    self[:url_fingerprint]     = Digest::MD5.hexdigest(self[:url])
    self[:storage_fingerprint] = self.class.fingerprint(data: [provider, self[:url]])
  end

  def self.fingerprint(data:)
    Digest::MD5.hexdigest(data.map(&:to_s).join(":"))
  end
end
