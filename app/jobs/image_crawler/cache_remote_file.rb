module ImageCrawler
  class CacheRemoteFile
    include Sidekiq::Worker
    sidekiq_options retry: false

    def self.schedule(url)
      fingerprint = RemoteFile.fingerprint(url)
      FindImage.perform_async("#{fingerprint}-icon", "icon", [url])
    end

    def perform(url, image)
      fingerprint = url.split("-").first
      RemoteFile.create!(
        fingerprint: fingerprint,
        original_url: image["original_url"],
        storage_url: image["processed_url"]
      )
    end
  end
end
