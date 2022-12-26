module ImageCrawler
  class CacheRemoteFile
    include Sidekiq::Worker
    sidekiq_options retry: false

    def self.schedule(url)
      fingerprint = RemoteFile.fingerprint(url)
      Pipeline::Find.perform_in(rand(1..10).seconds, "#{fingerprint}-icon", "icon", [url], nil, true)
    end

    def perform(url, image)
      fingerprint = url.split("-").first
      RemoteFile.create!(
        fingerprint: fingerprint,
        original_url: image["original_url"],
        storage_url: image["processed_url"],
        width: image["width"],
        height: image["height"],
      )
    end
  end
end
