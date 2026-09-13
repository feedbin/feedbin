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

    # Upload wrote the row; the legacy remote_files store is closed. The
    # callback exists so the preset keeps a job_class and the pipeline's
    # contract holds.
    def perform(url, image)
      Sidekiq.logger.info "CacheRemoteFile: landed id=#{url} storage_path=#{image["storage_path"]}"
    end
  end
end
