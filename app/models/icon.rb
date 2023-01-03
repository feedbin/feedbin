class Icon < ApplicationRecord
  enum provider: {twitter: 0, youtube: 1, favicon: 2, touch_icon: 3}, _prefix: true
  after_commit :cache_file, on: [:create, :update]

  def cache_file
    return if provider_favicon? || provider_touch_icon?
    return unless url_previously_changed?
    ImageCrawler::CacheRemoteFile.schedule(url)
  end

  def icon_url
    if provider_favicon? || provider_touch_icon?
      RemoteFile.favicon_url(url, fingerprint, params: {size: 32})
    else
      RemoteFile.icon_url(url, params: {size: 32})
    end
  end
end
