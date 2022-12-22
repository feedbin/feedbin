module ImageCrawler
  class RemoteImageCopy
    include Sidekiq::Worker
    include ImageCrawlerHelper
    sidekiq_options queue: :utility

    def perform(twitter_user_id)
      twitter_user = TwitterUser.find(twitter_user_id)
      return unless twitter_user.profile_image_url

      fingerprint = RemoteFile.fingerprint(twitter_user.profile_image)

      @preset_name = "icon"
      @public_id = "#{fingerprint}-icon"

      file = Down.download(twitter_user.profile_image_url)
      path = file.path

      image = Vips::Image.new_from_file(path)

      processed_url = File.open(path) do |file|
        options = STORAGE.dup
        options = options.merge(region: preset.region) unless preset.region.nil?
        response = Fog::Storage.new(options).put_object(bucket, image_name, file, storage_options)
        URI::HTTPS.build(
          host: response.data[:host],
          path: response.data[:path]
        ).to_s
      end

      RemoteFile.create_with(
        original_url: twitter_user.profile_image,
        storage_url: processed_url,
        width: image.width,
        height: image.height,
      ).find_or_create_by(fingerprint: fingerprint)

    ensure
      File.unlink(path) rescue Errno::ENOENT
    end

    def self.build
      TwitterUser.where.not(profile_image_url: nil).find_in_batches(batch_size: 10_000) do |items|
        Sidekiq::Client.push_bulk(
          "args" => items.map { [_1.id] },
          "class" => name,
          "queue" => get_sidekiq_options["queue"].to_s
        )
      end
    end
  end
end
