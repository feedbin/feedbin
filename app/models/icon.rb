class Icon < ApplicationRecord
  enum provider: {twitter: 0, youtube: 1, favicon: 2, touch_icon: 3}, _prefix: true
  after_commit :cache_file, on: [:create, :update]

  def cache_file
    ImageCrawler::CacheRemoteFile.schedule(url) if url_previously_changed?
  end

  def signed_url
    RemoteFile.signed_url(url)
  end
end
