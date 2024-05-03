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
  enum provider: [:entry_content, :entry_podcast, :entry_link, :feed_podcast, :remote_file]

  normalizes :url, with: -> url { url.strip }

  before_save :fingerprint_url

  private

  def fingerprint_url
    self[:url_fingerprint] = Digest::MD5.hexdigest(url)
  end

end
