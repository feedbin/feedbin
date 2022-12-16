module ImageCrawler
  module ImageCrawlerHelper
    CASCADE = Rails.root.join("lib/cascade/facefinder")
    PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
    PIGO_INSTALLED = File.executable?(PIGO)
    puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

    IMAGE_STORAGE = ENV["AWS_S3_BUCKET_IMAGES"] || ENV["AWS_S3_BUCKET"]
    IMAGE_PRESETS = {
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
        crop: :limit_crop,
        directory: "profile",
        validate: false,
        job_class: TwitterProfileImage
      },
      icon: {
        width: 400,
        height: 400,
        minimum_size: nil,
        crop: :limit_crop,
        bucket: RemoteFile::BUCKET,
        validate: false,
        job_class: CacheRemoteFile
      }
    }

    def preset
      OpenStruct.new(IMAGE_PRESETS[@preset_name.to_sym])
    end

    def send_to_feedbin(original_url:, storage_url:, placeholder_color:)
      preset.job_class.perform_async(@public_id, {
        "original_url"      => original_url,
        "processed_url"     => storage_url,
        "width"             => preset.width,
        "height"            => preset.height,
        "placeholder_color" => placeholder_color
      })
    end

    def image_name
      path = File.join(@public_id[0..2], "#{@public_id}.jpg")
      if preset.directory
        path = File.join(preset.directory, path)
      end
      path
    end

    def bucket
      preset.bucket || IMAGE_STORAGE
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