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
    avatar_url:           0,     # url based icon (microposts, mastodon, podcast)
    avatar_provider:      1,     # provider based icon (youtube, twitter)
    preview_entry:        2,     # main preview image
    preview_link:         3,     # link preview image
    remote_file:          4,     # adhoc images
    website_favicon:      5,     # favicon
    website_touch_icon:   6,     # apple touch icon
  }, prefix: true

  has_many :image_tags
  has_many :entries, through: :image_tags, source: :imageable, source_type: "Entry"
  has_many :feeds, through: :image_tags, source: :imageable, source_type: "Feed"

  scope :favicons, -> { where(provider: [:website_favicon, :website_touch_icon]) }
  scope :avatars,  -> { where(provider: [:avatar_url, :avatar_provider]) }

  before_validation :generate_columns

  store_accessor :settings, :original_storage_url, :final_url

  private

  def generate_columns
    self[:url_fingerprint] = Digest::MD5.hexdigest(url)
  end

  def self.fingerprint(data)
    Digest::MD5.hexdigest(data.map(&:to_s).join(":"))
  end

  def self.create_from_pipeline(data)
    record = create_with(data).create_or_find_by!(storage_fingerprint: data[:storage_fingerprint])
    record.update(data)
    record
  end
end
