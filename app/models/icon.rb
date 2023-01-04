class Icon < ApplicationRecord
  enum provider: {twitter: 0, youtube: 1, favicon: 2, touch_icon: 3}, _prefix: true

  def icon_url
    if provider_favicon? || provider_touch_icon?
      RemoteFile.favicon_url(url, fingerprint, params: {size: 32})
    else
      RemoteFile.icon_url(url, params: {size: 32})
    end
  end

  def self.create_from_cache(url:, provider:, provider_id:)
    saved = false
    fingerprint = RemoteFile.fingerprint(url)
    if file = RemoteFile.find_by_fingerprint(fingerprint)
      update = { provider_id:, provider:, url: }
      icon = create_with(update).find_or_create_by(provider_id:, provider:)
      icon.update(update)
      saved = true
    end
    saved
  end
end
