module ImageCrawler
  class Image
    ATTRIBUTES = %i[
      bytesize
      camo
      download_path
      entry_url
      feed_id
      final_url
      height
      width
      id
      image_urls
      meta_image_urls
      original_extension
      original_fingerprint
      original_url
      page_url
      placeholder_color
      preset_name
      processed_extension
      processed_path
      storage_url
      provider
      provider_id
      fingerprint
      webp_path
    ]


    attr_accessor *ATTRIBUTES

    BUCKET = ENV["AWS_S3_BUCKET_IMAGES"] || ENV["AWS_S3_BUCKET"]
    CONTENT_TYPES = {
      "webp" => "image/webp",
      "png"  => "image/png",
      "jpg"  => "image/jpeg"
    }.freeze
    PRESETS = {
      primary: {
        width: 542,
        height: 304,
        minimum_size: 20_000,
        crop: :smart_crop,
        format: "webp",
        validate: true,
        unified: true,
        job_class: EntryImage
      },
      twitter: {
        width: 542,
        height: 304,
        minimum_size: 10_000,
        crop: :smart_crop,
        format: "webp",
        validate: true,
        unified: true,
        job_class: TwitterLinkImage
      },
      youtube: {
        width: 542,
        height: 304,
        minimum_size: nil,
        crop: :fill_crop,
        format: "webp",
        validate: true,
        unified: true,
        job_class: EntryImage
      },
      podcast: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        format: "jpg",
        validate: true,
        unified: true,
        content_addressed: true,
        legacy_store: true,
        job_class: ItunesImage
      },
      podcast_feed: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        format: "jpg",
        validate: true,
        unified: true,
        content_addressed: true,
        legacy_store: true,
        job_class: ItunesFeedImage
      },
      icon: {
        width: 400,
        height: 400,
        minimum_size: nil,
        crop: :limit_crop,
        bucket: RemoteFile::BUCKET,
        region: RemoteFile::REGION,
        validate: false,
        job_class: CacheRemoteFile
      },
      favicon: {
        width: 32,
        height: 32,
        minimum_size: nil,
        crop: :icon_crop,
        format: "png",
        validate: false,
        unified: true,
        content_addressed: true,
        legacy_store: false,
        job_class: nil
      },
      touch_icon: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :icon_crop,
        format: "png",
        validate: false,
        unified: true,
        content_addressed: true,
        legacy_store: false,
        job_class: nil
      }
    }

    def self.new_with_attributes(id:, preset_name:, image_urls:, provider:, provider_id:, **other)
      arguments = Hash[binding.local_variables.map{ [_1, binding.local_variable_get(_1)]}]
      arguments.delete(:arguments)
      other = arguments.delete(:other)
      new(other.merge(arguments))
    end

    # Ignores attributes it does not recognize: pipeline jobs are retry: false
    # and run on host-local queues, so payloads written by a newer deploy must
    # not crash a not-yet-deployed consumer (and vice versa).
    def initialize(data = {})
      data.each do |name, value|
        if ATTRIBUTES.include?(name.to_sym)
          instance_variable_set("@#{name}", value)
        end
      end
    end

    def to_h
      {}.tap do |hash|
        ATTRIBUTES.each do |attribute|
          hash[attribute] = self.send(attribute)
        end
      end
    end

    def preset
      OpenStruct.new(PRESETS[preset_name.to_sym])
    end

    def validate?
      preset.validate || false
    end

    def send_to_feedbin(include_unified: true)
      # A preset with no callback job stores the row and stops. The icon
      # presets ship before their tenants do; each tenant adds its job_class
      # when it lands.
      return if preset.job_class.nil?

      payload = {
        "original_url"      => final_url,
        "processed_url"     => storage_url,
        "width"             => width,
        "height"            => height,
        "placeholder_color" => placeholder_color
      }
      if unified? && include_unified
        payload["storage_path"] = storage_path
        payload["bytesize"]     = bytesize
        payload["provider"]     = provider_label
      end
      preset.job_class.perform_async(id, payload)
    end

    def create_image
      record = ::Image.with_storage_lock(storage_path) do
        ::Image.attach!(
          provider: provider,
          provider_id: provider_id,
          feed_id: feed_id,
          url: original_url,
          variant: variant,
          image_fingerprint: fingerprint,
          original_fingerprint: original_fingerprint,
          storage_path: storage_path,
          width: width,
          height: height,
          bytesize: bytesize,
          placeholder_color: placeholder_color,
          data: {
            "legacy_storage_url" => storage_url,
            "preset"             => preset_name,
            "final_url"          => final_url
          }
        )
      end

      # The row moved to a different object, so the old one may now be
      # unreferenced. Swept in its own job because it is a different lock key
      # than the one held above, and taking both here would invert the sorted
      # acquisition order that keeps GC batches from deadlocking.
      if record.saved_change_to_storage_path? && (replaced = record.storage_path_before_last_save)
        ImageReplacementCollector.perform_async([replaced])
      end

      record
    end

    # create_image's counterpart, for when a re-upload after a confirmed-
    # vanished object also fails: the row create_image just wrote now
    # references a storage_path with nothing behind it, which is worse than
    # no row at all -- unchanged? would pin every later crawl of a
    # content-addressed preset on the dead path forever, and Dedupe#attach
    # only checks that a row exists, not that its object does, so it would
    # keep attaching more rows to nothing. Re-takes the lock create_image
    # used (already released by the time we get here) and re-checks
    # storage_path first, so a concurrent crawl that already replaced this
    # row with a real object is left alone.
    def drop_image
      ::Image.with_storage_lock(storage_path) do
        record = ::Image.find_by(provider: provider, provider_id: provider_id.to_s)
        record.destroy if record && record.storage_path == storage_path
      end
    end

    def unified?
      preset.unified == true && ENV["R2_BUCKET_IMAGES"].present?
    end

    def storage_path
      if content_addressed?
        ::Image.content_storage_path_for(original_fingerprint, variant, preset.format)
      else
        ::Image.storage_path_for(original_url, variant, preset.format)
      end
    end

    # The icon family: storage identity comes from the original bytes rather
    # than the URL, and the pipeline always downloads before deciding anything.
    def content_addressed?
      preset.content_addressed == true
    end

    # legacy_store? only decides whether the legacy S3 object gets written --
    # dual-storing also requires unified?. Entry presets (primary/twitter/
    # youtube) are both, so they dual-store. podcast, podcast_feed, and the
    # plain icon preset say nothing here either, but aren't unified?, so they
    # write only the legacy object. favicon/touch_icon are the only presets
    # that turn this off, writing only the R2 object.
    def legacy_store?
      preset.legacy_store != false
    end

    # The R2 object is the webp for the dual-format entry presets and the
    # single PNG for icons.
    def r2_source_path
      webp_path || processed_path
    end

    # The stored-object identity pairs variant with either the url (entry
    # presets) or original_fingerprint (the content-addressed icon family --
    # see content_addressed? above): presets sharing an output geometry
    # share objects, presets that differ (podcast 200x200 vs entry 542x304)
    # never collide even for the same source.
    def variant
      "#{preset.width}x#{preset.height}"
    end

    def provider_label
      ::Image.providers.key(provider)
    end

    def r2_bucket
      ENV["R2_BUCKET_IMAGES"]
    end

    def r2_storage_options
      {
        "Content-Type"  => CONTENT_TYPES.fetch(preset.format),
        "Cache-Control" => "max-age=315360000, public, immutable"
      }
    end

    def image_name
      path = File.join(id[0..2], "#{id}.#{processed_extension}")
      if preset.directory
        path = File.join(preset.directory, path)
      end
      path
    end

    def bucket
      preset.bucket || BUCKET
    end

    def trace(message:, metadata: {})
      defaults = {
        public_id: id,
        preset: preset_name,
      }.merge(metadata)

      Sidekiq.logger.info "Image trace: #{message} #{defaults.map { |k, v| "#{k}=#{v}" }.join(" ")}"
    end

    def storage_options
      {
        "Cache-Control" => "max-age=315360000, public",
        "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
        "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY",
        "x-amz-acl" => "public-read"
      }
    end

  end
end
