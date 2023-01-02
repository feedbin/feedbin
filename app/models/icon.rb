class Icon < ApplicationRecord
  enum provider: {twitter: 0, youtube: 1, favicon: 2, touch_icon: 3}, _prefix: true
  after_commit :cache_file, on: [:create, :update]

  def cache_file
    return if provider_favicon? || provider_touch_icon?
    return unless url_previously_changed?
    ImageCrawler::CacheRemoteFile.schedule(url)
  end

  def signed_url
    RemoteFile.signed_url(url)
  end
end
