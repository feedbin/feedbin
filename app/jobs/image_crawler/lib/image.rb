module ImageCrawler
  class Image
    ATTRIBUTES = %i[
      camo
      download_path
      entry_url
      final_url
      height
      width
      id
      image_urls
      original_extension
      original_url
      placeholder_color
      preset_name
      processed_extension
      processed_path
      storage_url
      storage_url_next
      original_storage_url
      provider
      provider_id
      fingerprint
    ]


    attr_accessor *ATTRIBUTES

    BUCKET = ENV["AWS_S3_BUCKET_IMAGES"] || ENV["AWS_S3_BUCKET"]
    PRESETS = {
      primary: {
        width: 542,
        height: 304,
        minimum_size: 20_000,
        crop: :smart_crop,
        validate: true,
        job_class: EntryImage
      },
      twitter: {
        width: 542,
        height: 304,
        minimum_size: 10_000,
        crop: :smart_crop,
        validate: true,
        job_class: TwitterLinkImage
      },
      youtube: {
        width: 542,
        height: 304,
        minimum_size: nil,
        crop: :fill_crop,
        validate: true,
        job_class: EntryImage
      },
      podcast: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        validate: true,
        job_class: ItunesImage
      },
      podcast_feed: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
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
      }
    }

    def self.new_with_attributes(id:, preset_name:, image_urls:, provider:, provider_id:, **other)
      arguments = Hash[binding.local_variables.map{ [_1, binding.local_variable_get(_1)]}]
      arguments.delete(:arguments)
      other = arguments.delete(:other)
      new(other.merge(arguments))
    end

    def initialize(data = {})
      data.each do |name, value|
        if ATTRIBUTES.include?(name.to_sym)
          instance_variable_set("@#{name}", value)
        else
          raise ArgumentError.new("Unknown #{self.class.name} attribute: #{name}")
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

    def send_to_feedbin
      preset.job_class.perform_async(id, {
        "original_url"      => final_url,
        "processed_url"     => storage_url,
        "width"             => width,
        "height"            => height,
        "placeholder_color" => placeholder_color
      })
      image_record = create_image
      preset.job_class.const_get(:Receiver).perform_async(provider_id, image_record.id)
    end

    def create_image
      ::Image.create_from_pipeline({
        provider: provider,
        provider_id: provider_id,
        url: original_url,
        final_url: final_url,
        storage_url: storage_url_next,
        original_storage_url: storage_url,
        image_fingerprint: fingerprint,
        width: width,
        height: height,
        placeholder_color: placeholder_color,
        storage_fingerprint: storage_fingerprint
      })
    end

    def image_name
      path = File.join(id[0..2], "#{id}.#{processed_extension}")
      if preset.directory
        path = File.join(preset.directory, path)
      end
      path
    end

    def storage_fingerprint
      ::Image.fingerprint([provider, original_url])
    end

    def storage_path
      File.join(storage_fingerprint[0..2], storage_fingerprint)
    end

    def bucket
      preset.bucket || BUCKET
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
