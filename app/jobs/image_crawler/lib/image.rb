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
        job_class: ItunesImage
      },
      podcast_feed: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        format: "jpg",
        validate: true,
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
      ::Image.with_storage_lock(storage_path) do
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

    # Entry presets dual-store: the legacy S3 jpg is what pre-R2 clients read.
    # Icons store one object. Presets that say nothing keep dual-storing.
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

    def url_fingerprint
      ::Image.url_fingerprint_for(original_url, variant)
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
