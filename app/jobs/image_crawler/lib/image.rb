module ImageCrawler
  class Image
    ATTRIBUTES = %i[id preset_name image_urls entry_url download_path
                    original_extension original_url final_url
                    storage_url processed_path processed_extension
                    width height placeholder_color camo]


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
      profile: {
        width: 400,
        height: 400,
        minimum_size: nil,
        crop: :icon_crop,
        directory: "profile",
        validate: false,
        job_class: TwitterProfileImage
      },
      icon: {
        width: 400,
        height: 400,
        minimum_size: nil,
        crop: :icon_crop,
        bucket: RemoteFile::BUCKET,
        region: RemoteFile::REGION,
        validate: false,
        job_class: CacheRemoteFile
      },
      favicon: {
        width: 400,
        height: 400,
        minimum_size: nil,
        crop: :icon_crop,
        bucket: RemoteFile::BUCKET,
        region: RemoteFile::REGION,
        validate: false,
        job_class: IconCrawler::Receive,
        job_args: :image
      }
    }

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
