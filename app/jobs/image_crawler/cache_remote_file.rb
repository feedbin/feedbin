module ImageCrawler
  class CacheRemoteFile
    include Sidekiq::Worker
    sidekiq_options retry: false

    def self.schedule(url)
      fingerprint = RemoteFile.fingerprint(url)
      return if RemoteFile.where(fingerprint: fingerprint).exists?
      image = Image.new_with_attributes(
        id: "#{fingerprint}-icon",
        preset_name: "icon",
        image_urls: [url],
        provider: ::Image.providers[:remote_file],
        provider_id: fingerprint,
        camo: true
      )

      Pipeline::Find.perform_in(rand(1..10).seconds, image.to_h)
    end

    def perform(url, image)
      fingerprint = url.split("-").first
      update = {
        fingerprint: fingerprint,
        original_url: image["original_url"],
        storage_url: image["processed_url"],
        width: image["width"],
        height: image["height"],
      }
      file = RemoteFile.create_with(update).find_or_create_by(fingerprint: fingerprint)
      file.update(update)
    end
  end
end
