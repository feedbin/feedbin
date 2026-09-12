module ImageCrawler
  class CacheRemoteFile
    include Sidekiq::Worker
    sidekiq_options retry: false

    # kind is the caller's to say: a remote file is whatever URL a view
    # asked to proxy, and nothing about the URL says what the picture is.
    def self.schedule(url, kind:)
      fingerprint = RemoteFile.fingerprint(url)
      image = Image.new_with_attributes(
        id: "#{fingerprint}-icon",
        kind: kind,
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
      RemoteFile.create_with(
        original_url: image["original_url"],
        storage_url: image["processed_url"],
        width: image["width"],
        height: image["height"],
      ).create_or_find_by!(fingerprint: fingerprint)
    end
  end
end
