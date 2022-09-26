module ImageCrawler
  module ImageHelper
    CASCADE = Rails.root.join("lib/cascade/facefinder")
    PIGO = ENV["PIGO_PATH"] || `which pigo`.chomp
    PIGO_INSTALLED = File.executable?(PIGO)
    puts "Pigo missing. Add it to your path or set ENV['PIGO_PATH']. From https://github.com/esimov/pigo" unless PIGO_INSTALLED

    IMAGE_STORAGE = ENV["AWS_S3_BUCKET_IMAGES"] || ENV["AWS_S3_BUCKET"]
    STORAGE_OPTIONS = CarrierWave.configure { _1.fog_credentials }

    IMAGE_PRESETS = {
      primary: {
        width: 542,
        height: 304,
        minimum_size: 20_000,
        crop: :smart_crop,
        job_class: EntryImage
      },
      twitter: {
        width: 542,
        height: 304,
        minimum_size: 10_000,
        crop: :smart_crop,
        job_class: TwitterLinkImage
      },
      youtube: {
        width: 542,
        height: 304,
        minimum_size: nil,
        crop: :fill_crop,
        job_class: EntryImage
      },
      podcast: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        job_class: ItunesImage
      },
      podcast_feed: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        job_class: ItunesFeedImage
      }
    }

    def preset
      OpenStruct.new(IMAGE_PRESETS[@preset_name.to_sym])
    end

    def send_to_feedbin(original_url:, storage_url:)
      preset.job_class.perform_async(@public_id, {
        "original_url" => original_url,
        "processed_url" => storage_url,
        "width" => preset.width,
        "height" => preset.height
      })
    end

    def image_name
      File.join(@public_id[0..6], "#{@public_id}.jpg")
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